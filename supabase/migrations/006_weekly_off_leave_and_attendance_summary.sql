-- Sundays are weekly off days. The server rejects punches even if a client is modified.
alter table public.attendance_correction_requests
  add column if not exists request_type text not null default 'missed_punch';

alter table public.attendance_correction_requests
  add constraint attendance_correction_request_type_check
  check (request_type in ('missed_punch', 'incorrect_punch'));

drop policy if exists correction_requests_read_scoped on public.attendance_correction_requests;
create policy correction_requests_read_scoped
on public.attendance_correction_requests for select to authenticated
using (
  user_id = (select auth.uid())
  or (select private.is_admin())
  or private.can_review_user(user_id)
);

drop policy if exists correction_requests_review on public.attendance_correction_requests;
create policy correction_requests_review
on public.attendance_correction_requests for update to authenticated
using ((select private.is_admin()) or private.can_review_user(user_id))
with check ((select private.is_admin()) or private.can_review_user(user_id));

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id),
  leave_type text not null check (leave_type in ('annual', 'sick', 'personal', 'unpaid')),
  start_date date not null,
  end_date date not null,
  reason text not null check (length(trim(reason)) between 1 and 1200),
  status text not null default 'submitted' check (status in ('submitted', 'approved', 'rejected')),
  review_comment text not null default '',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check (end_date >= start_date),
  check (start_date <> end_date or extract(dow from start_date)::integer <> 0),
  check (
    (status = 'submitted' and reviewed_by is null and reviewed_at is null)
    or (status in ('approved', 'rejected') and reviewed_by is not null and reviewed_at is not null)
  )
);

create index if not exists leave_requests_user_created_idx
  on public.leave_requests(user_id, created_at desc);
create index if not exists leave_requests_status_dates_idx
  on public.leave_requests(status, start_date, end_date);

alter table public.leave_requests enable row level security;

drop policy if exists leave_requests_read_scoped on public.leave_requests;
create policy leave_requests_read_scoped
on public.leave_requests for select to authenticated
using (
  user_id = (select auth.uid())
  or (select private.is_admin())
  or private.can_review_user(user_id)
);

drop policy if exists leave_requests_insert_self on public.leave_requests;
create policy leave_requests_insert_self
on public.leave_requests for insert to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'submitted'
  and reviewed_by is null
  and reviewed_at is null
);

drop policy if exists leave_requests_review on public.leave_requests;
create policy leave_requests_review
on public.leave_requests for update to authenticated
using (
  status = 'submitted'
  and ((select private.is_admin()) or private.can_review_user(user_id))
)
with check (
  status in ('approved', 'rejected')
  and reviewed_by = (select auth.uid())
  and reviewed_at is not null
  and ((select private.is_admin()) or private.can_review_user(user_id))
);

grant select, insert on public.leave_requests to authenticated;
grant update (status, review_comment, reviewed_by, reviewed_at)
  on public.leave_requests to authenticated;

create or replace function public.my_attendance_summary(p_month_start date default null)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, pg_temp
as $function$
declare
  uid uuid := auth.uid();
  month_start date := date_trunc('month', coalesce(p_month_start, current_date))::date;
  month_end date;
  present_days integer := 0;
  leave_days integer := 0;
begin
  if uid is null then
    raise exception 'Sign in to view attendance totals.' using errcode = '28000';
  end if;

  month_end := (month_start + interval '1 month')::date;

  select count(*)::integer into present_days
  from (
    select (session.started_at at time zone 'UTC')::date as present_date
    from public.attendance_sessions as session
    where session.user_id = uid
      and (session.started_at at time zone 'UTC')::date >= month_start
      and (session.started_at at time zone 'UTC')::date < month_end
      and extract(dow from session.started_at at time zone 'UTC')::integer <> 0
    union
    select correction.event_date as present_date
    from public.attendance_correction_requests as correction
    where correction.user_id = uid
      and correction.status = 'approved'
      and correction.event_date >= month_start
      and correction.event_date < month_end
      and extract(dow from correction.event_date)::integer <> 0
  ) as present_dates;

  select count(distinct workday.day)::integer into leave_days
  from public.leave_requests as request
  cross join lateral generate_series(
    greatest(request.start_date, month_start)::timestamp,
    least(request.end_date, month_end - 1)::timestamp,
    interval '1 day'
  ) as workday(day)
  where request.user_id = uid
    and request.status = 'approved'
    and request.start_date < month_end
    and request.end_date >= month_start
    and extract(dow from workday.day)::integer <> 0;

  return jsonb_build_object(
    'month_start', month_start,
    'present_days', coalesce(present_days, 0),
    'approved_leave_days', coalesce(leave_days, 0),
    'weekly_off_day', 'Sunday'
  );
end;
$function$;

revoke all on function public.my_attendance_summary(date) from public, anon;
grant execute on function public.my_attendance_summary(date) to authenticated;

create or replace function private.record_attendance_impl(
  p_action text,
  p_site_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_mocked_signal boolean default false
)
returns jsonb language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare
  uid uuid := auth.uid();
  site public.attendance_sites%rowtype;
  active_session public.attendance_sessions%rowtype;
  measured_distance double precision;
  rejection text;
  session_id uuid;
begin
  if uid is null then
    return jsonb_build_object('accepted', false, 'reason', 'Sign in before recording attendance.');
  end if;
  perform pg_advisory_xact_lock(hashtext(uid::text));

  if not exists (select 1 from public.profiles where id = uid and is_active = true) then
    rejection := 'This account is not active.';
  elsif extract(dow from (now() at time zone 'UTC'))::integer = 0 then
    rejection := 'Sunday is the weekly off day. Attendance punches are unavailable.';
  elsif p_action is null or p_action not in ('in', 'out') then
    rejection := 'Unknown attendance action.';
  elsif p_latitude is null or p_longitude is null
    or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    rejection := 'Location coordinates are invalid.';
  elsif p_accuracy_meters is null or p_accuracy_meters < 0 or p_accuracy_meters > 35 then
    rejection := 'GPS accuracy must be 35 metres or better.';
  elsif coalesce(p_mocked_signal, false) then
    rejection := 'A simulated device location was flagged.';
  else
    select * into site
    from public.attendance_sites
    where id = p_site_id and is_active = true;

    if not found then
      rejection := 'This attendance site is inactive or unavailable.';
    elsif site.kind = 'project' and not private.can_access_project(site.project_id) then
      rejection := 'You are not assigned to this project site.';
    else
      measured_distance := private.haversine_meters(
        p_latitude, p_longitude, site.latitude, site.longitude
      );
      if measured_distance > site.radius_meters then
        rejection := 'You are outside the approved site radius.';
      end if;
    end if;
  end if;

  if rejection is not null then
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
    values (
      uid, 'attendance.rejected', 'attendance_sites', p_site_id::text,
      jsonb_build_object(
        'reason', rejection, 'action', p_action,
        'accuracy_meters', p_accuracy_meters,
        'mocked_signal', coalesce(p_mocked_signal, false)
      )
    );
    return jsonb_build_object('accepted', false, 'reason', rejection);
  end if;

  select * into active_session
  from public.attendance_sessions
  where user_id = uid and status = 'open'
  for update;

  if p_action = 'in' and active_session.id is not null then
    rejection := 'You are already punched in.';
  elsif p_action = 'out' and active_session.id is null then
    rejection := 'There is no open attendance session to punch out.';
  end if;

  if rejection is not null then
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
    values (
      uid, 'attendance.rejected', 'attendance_sessions', coalesce(active_session.id::text, ''),
      jsonb_build_object('reason', rejection, 'action', p_action)
    );
    return jsonb_build_object('accepted', false, 'reason', rejection);
  end if;

  if p_action = 'in' then
    insert into public.attendance_sessions(user_id, site_id, status)
    values (uid, site.id, 'open') returning id into session_id;
  else
    session_id := active_session.id;
    update public.attendance_sessions
    set ended_at = now(), status = 'closed'
    where id = session_id;
  end if;

  insert into public.attendance_events(
    session_id, user_id, site_id, site_name, action, latitude, longitude,
    accuracy_meters, distance_meters, risk_flag
  ) values (
    session_id, uid, site.id, site.name, p_action, p_latitude, p_longitude,
    p_accuracy_meters, measured_distance, null
  );

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (
    uid, 'attendance.' || p_action, 'attendance_sessions', session_id::text,
    jsonb_build_object(
      'site_id', site.id, 'distance_meters', round(measured_distance),
      'accuracy_meters', p_accuracy_meters
    )
  );

  return jsonb_build_object(
    'accepted', true, 'session_id', session_id, 'action', p_action,
    'site_name', site.name, 'distance_meters', round(measured_distance)
  );
end;
$function$;
