-- Let an employee close the session they already opened even if it is Sunday,
-- the site was deactivated, or their project assignment changed during the shift.
-- Punch-in checks remain restricted to active authorized sites and weekdays.
create or replace function private.record_attendance_impl(
  p_action text,
  p_site_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_mocked_signal boolean default false
)
returns jsonb
language plpgsql
security definer
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

  if p_action is null or p_action not in ('in', 'out') then
    rejection := 'Unknown attendance action.';
  elsif not exists (select 1 from public.profiles where id = uid and is_active = true) then
    rejection := 'This account is not active.';
  elsif p_latitude is null or p_longitude is null
    or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    rejection := 'Location coordinates are invalid.';
  elsif p_accuracy_meters is null or p_accuracy_meters < 0 or p_accuracy_meters > 35 then
    rejection := 'GPS accuracy must be 35 metres or better.';
  elsif coalesce(p_mocked_signal, false) then
    rejection := 'A simulated device location was flagged.';
  end if;

  if rejection is null then
    select * into active_session
    from public.attendance_sessions
    where user_id = uid and status = 'open'
    for update;

    if p_action = 'in' and active_session.id is not null then
      rejection := 'You are already punched in.';
    elsif p_action = 'out' and active_session.id is null then
      rejection := 'There is no open attendance session to punch out.';
    end if;
  end if;

  if rejection is null and p_action = 'out' then
    -- A punch-out always belongs to the open shift's original site. Ignore a
    -- stale or changed site id supplied by the client, but still require GPS
    -- to be inside that site's configured radius.
    select * into site
    from public.attendance_sites
    where id = active_session.site_id;
    if not found then
      rejection := 'The original attendance site is unavailable; submit a correction request.';
    end if;
  elsif rejection is null then
    select * into site
    from public.attendance_sites
    where id = p_site_id and is_active = true;

    if not found then
      rejection := 'This attendance site is inactive or unavailable.';
    elsif site.kind = 'project' and not private.can_access_project(site.project_id) then
      rejection := 'You are not assigned to this project site.';
    elsif extract(dow from (now() at time zone 'UTC'))::integer = 0 then
      rejection := 'Sunday is the weekly off day. Punch-in is unavailable.';
    end if;
  end if;

  if rejection is null then
    measured_distance := private.haversine_meters(
      p_latitude, p_longitude, site.latitude, site.longitude
    );
    if measured_distance > site.radius_meters then
      rejection := 'You are outside the approved site radius.';
    end if;
  end if;

  if rejection is not null then
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
    values (
      uid, 'attendance.rejected',
      case when p_action = 'out' then 'attendance_sessions' else 'attendance_sites' end,
      coalesce(active_session.id::text, p_site_id::text, ''),
      jsonb_build_object(
        'reason', rejection, 'action', p_action,
        'accuracy_meters', p_accuracy_meters,
        'mocked_signal', coalesce(p_mocked_signal, false)
      )
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

-- Provide the caller's currently open shift site to the app, including if an
-- administrator deactivated it or the caller's project assignment changed.
create or replace function public.my_open_attendance_site()
returns jsonb
language sql
security definer
set search_path to 'pg_catalog', 'public', 'auth', 'pg_temp'
as $function$
  select jsonb_build_object(
    'id', site.id,
    'name', site.name,
    'kind', site.kind,
    'latitude', site.latitude,
    'longitude', site.longitude,
    'radius_meters', site.radius_meters
  )
  from public.attendance_sessions as session
  join public.attendance_sites as site on site.id = session.site_id
  where session.user_id = auth.uid()
    and session.status = 'open'
  limit 1
$function$;

revoke all on function public.my_open_attendance_site() from public, anon;
grant execute on function public.my_open_attendance_site() to authenticated;
