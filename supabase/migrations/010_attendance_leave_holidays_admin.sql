-- Attendance reporting, carry-forward paid leave, holiday calendar and private
-- request reasons. Sunday is a paid weekly off day and is credited as present.
alter table public.profiles
  add column if not exists leave_accrual_start date,
  add column if not exists leave_opening_balance numeric not null default 0,
  add column if not exists saturday_full_day_credit boolean not null default false;

update public.profiles
set leave_accrual_start = date_trunc('month', created_at at time zone 'UTC')::date
where leave_accrual_start is null;

alter table public.profiles alter column leave_accrual_start set default date_trunc('month', current_date)::date;
alter table public.profiles alter column leave_accrual_start set not null;
alter table public.profiles drop constraint if exists profiles_leave_opening_balance_nonnegative;
alter table public.profiles add constraint profiles_leave_opening_balance_nonnegative
  check (leave_opening_balance >= 0);
revoke select on public.profiles from authenticated;
grant select (id,display_name,role,is_active,created_at,updated_at,employee_id,saturday_full_day_credit)
  on public.profiles to authenticated;

create table if not exists public.paid_holidays (
  id uuid primary key default gen_random_uuid(),
  holiday_date date not null unique,
  name text not null check (length(trim(name)) between 1 and 120),
  paid_days numeric(3,1) not null default 1 check (paid_days = 1),
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.paid_holidays enable row level security;
drop policy if exists paid_holidays_read_authenticated on public.paid_holidays;
create policy paid_holidays_read_authenticated on public.paid_holidays
  for select to authenticated using (true);
drop policy if exists paid_holidays_admin_write on public.paid_holidays;
create policy paid_holidays_admin_write on public.paid_holidays
  for all to authenticated
  using ((select private.is_admin()))
  with check ((select private.is_admin()));
grant select, insert, update, delete on public.paid_holidays to authenticated;
drop trigger if exists updated_at_paid_holidays on public.paid_holidays;
create trigger updated_at_paid_holidays before update on public.paid_holidays
for each row execute function public.set_updated_at();
drop trigger if exists audit_paid_holidays on public.paid_holidays;
create trigger audit_paid_holidays after insert or update or delete on public.paid_holidays
for each row execute function private.write_audit_row();

create or replace function private.attendance_day_credit(p_user_id uuid, p_date date)
returns numeric
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
  select case
    when p_date is null or extract(dow from p_date)::integer = 0 then 0::numeric
    when exists (select 1 from public.paid_holidays holiday where holiday.holiday_date=p_date) then 0::numeric
    when extract(dow from p_date)::integer = 6
      and not coalesce((select profile.saturday_full_day_credit from public.profiles profile where profile.id=p_user_id),false)
      then 0.5::numeric
    else 1::numeric
  end
$function$;
revoke all on function private.attendance_day_credit(uuid,date) from public, anon, authenticated;

create or replace function private.workday_count(p_user_id uuid, p_start date, p_end date)
returns numeric
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
  select coalesce(sum(private.attendance_day_credit(p_user_id, day.value::date)),0)::numeric
  from generate_series(p_start, p_end, interval '1 day') as day(value)
$function$;
revoke all on function private.workday_count(uuid,date,date) from public, anon, authenticated;

create or replace function private.paid_leave_balance_for(p_user_id uuid, p_as_of date default current_date)
returns numeric
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
  with profile_balance as (
    select leave_opening_balance as opening,
      greatest(0,
        (extract(year from age(date_trunc('month', p_as_of)::date, leave_accrual_start))::integer * 12)
        + extract(month from age(date_trunc('month', p_as_of)::date, leave_accrual_start))::integer
        + 1
      ) as accrued_months
    from public.profiles where id = p_user_id and is_active
  ), consumed as (
    select coalesce(sum(private.workday_count(p_user_id, request.start_date, request.end_date)), 0) as days
    from public.leave_requests request
    where request.user_id = p_user_id
      and request.status = 'approved'
      and request.leave_type = 'annual'
      and request.start_date <= p_as_of
  )
  select greatest(0, coalesce(profile_balance.opening + profile_balance.accrued_months - consumed.days, 0))::numeric
  from profile_balance cross join consumed
$function$;
revoke all on function private.paid_leave_balance_for(uuid,date) from public, anon, authenticated;

create or replace function public.my_attendance_summary(p_month_start date default null)
returns jsonb
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare
  uid uuid := auth.uid();
  month_start date := date_trunc('month', coalesce(p_month_start, current_date))::date;
  month_end date;
  employment_start date;
  present_days numeric;
  leave_days numeric;
  holiday_days integer;
  worked_minutes integer;
  saturday_full_day_credit boolean;
begin
  if uid is null then
    raise exception 'Sign in to view attendance totals.' using errcode = '28000';
  end if;
  month_end := (month_start + interval '1 month')::date;
  select leave_accrual_start, profiles.saturday_full_day_credit
  into employment_start, saturday_full_day_credit from public.profiles where id=uid;

  with credited_days as (
    select day.value::date as work_date, 1::numeric as credit
    from generate_series(greatest(month_start, employment_start), least(month_end - 1, current_date), interval '1 day') as day(value)
    where extract(dow from day.value)::integer = 0
    union
    select holiday.holiday_date, 1::numeric
    from public.paid_holidays holiday
    where holiday.holiday_date >= month_start and holiday.holiday_date < month_end
      and holiday.holiday_date <= current_date and holiday.holiday_date >= employment_start
    union
    select distinct (session.started_at at time zone 'UTC')::date,
      private.attendance_day_credit(uid,(session.started_at at time zone 'UTC')::date)
    from public.attendance_sessions session
    where session.user_id = uid
      and (session.started_at at time zone 'UTC')::date >= greatest(month_start,employment_start)
      and (session.started_at at time zone 'UTC')::date < month_end
      and (session.started_at at time zone 'UTC')::date <= current_date
      and extract(dow from session.started_at at time zone 'UTC')::integer <> 0
      and not exists (select 1 from public.paid_holidays h where h.holiday_date = (session.started_at at time zone 'UTC')::date)
    union
    select correction.event_date, private.attendance_day_credit(uid,correction.event_date)
    from public.attendance_correction_requests correction
    where correction.user_id = uid and correction.status = 'approved'
      and correction.event_date >= greatest(month_start,employment_start) and correction.event_date < month_end
      and correction.event_date <= current_date
      and extract(dow from correction.event_date)::integer <> 0
      and not exists (select 1 from public.paid_holidays h where h.holiday_date = correction.event_date)
  )
  select coalesce(sum(credit),0)::numeric into present_days from credited_days;

  select coalesce(sum(private.attendance_day_credit(uid,leave_day.work_date)),0)::numeric into leave_days
  from (
    select distinct day.value::date as work_date
    from public.leave_requests request
    cross join lateral generate_series(greatest(request.start_date, month_start), least(request.end_date, month_end - 1, current_date), interval '1 day') day(value)
    where request.user_id = uid and request.status = 'approved'
      and request.start_date < month_end and request.end_date >= month_start
  ) leave_day;

  select count(*)::integer into holiday_days from public.paid_holidays holiday
  where holiday.holiday_date >= month_start and holiday.holiday_date < month_end
    and holiday.holiday_date <= current_date
    and holiday.holiday_date >= employment_start
    and extract(dow from holiday.holiday_date)::integer <> 0;

  select coalesce(sum(greatest(0, extract(epoch from (coalesce(session.ended_at, now()) - session.started_at)) / 60)::integer), 0)::integer
  into worked_minutes
  from public.attendance_sessions session
  where session.user_id = uid
    and (session.started_at at time zone 'UTC')::date >= month_start
    and (session.started_at at time zone 'UTC')::date < month_end;

  return jsonb_build_object(
    'month_start', month_start,
    'present_days', coalesce(present_days, 0),
    'approved_leave_days', coalesce(leave_days, 0),
    'paid_holiday_days', coalesce(holiday_days, 0),
    'worked_minutes', coalesce(worked_minutes, 0),
    'paid_leave_balance', private.paid_leave_balance_for(uid, current_date),
    'saturday_full_day_credit', saturday_full_day_credit,
    'weekly_off_day', 'Sunday'
  );
end;
$function$;
revoke all on function public.my_attendance_summary(date) from public, anon;
grant execute on function public.my_attendance_summary(date) to authenticated;

create or replace function public.admin_attendance_report(p_month_start date default null)
returns table(
  user_id uuid, employee_id text, display_name text, saturday_full_day_credit boolean,
  present_days numeric, leave_days numeric, absent_days numeric, paid_holiday_days integer,
  worked_minutes integer, paid_leave_balance numeric, leave_accrual_start date,
  leave_opening_balance numeric, daily jsonb
)
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare
  month_start date := date_trunc('month', coalesce(p_month_start, current_date))::date;
  month_end date;
begin
  if not private.is_admin() then
    raise exception 'Only an Admin can export workspace attendance.' using errcode = '42501';
  end if;
  month_end := (month_start + interval '1 month')::date;

  return query
  with dates as (
    select day.value::date as work_date from generate_series(month_start, least(month_end - 1, current_date), interval '1 day') day(value)
  ), staff as (
    select p.id, p.employee_id, p.display_name, p.saturday_full_day_credit,
      p.leave_accrual_start, p.leave_opening_balance
    from public.profiles p where p.is_active
  ), day_facts as (
    select s.id as uid, d.work_date,
      exists(select 1 from public.paid_holidays h where h.holiday_date = d.work_date) as is_holiday,
      extract(dow from d.work_date)::integer = 0 as is_sunday,
      exists(select 1 from public.attendance_sessions a where a.user_id=s.id and (a.started_at at time zone 'UTC')::date=d.work_date) as has_session,
      exists(select 1 from public.leave_requests l where l.user_id=s.id and l.status='approved' and l.start_date<=d.work_date and l.end_date>=d.work_date) as on_leave,
      (select min(e.created_at) from public.attendance_events e where e.user_id=s.id and (e.created_at at time zone 'UTC')::date=d.work_date and e.action='in') as punch_in,
      (select max(e.created_at) from public.attendance_events e where e.user_id=s.id and (e.created_at at time zone 'UTC')::date=d.work_date and e.action='out') as punch_out,
      (select h.name from public.paid_holidays h where h.holiday_date=d.work_date limit 1) as holiday_name,
      (select l.leave_type from public.leave_requests l where l.user_id=s.id and l.status='approved' and l.start_date<=d.work_date and l.end_date>=d.work_date order by l.created_at limit 1) as leave_type,
      coalesce((select sum(greatest(0, extract(epoch from (coalesce(a.ended_at, now())-a.started_at))/60)::integer) from public.attendance_sessions a where a.user_id=s.id and (a.started_at at time zone 'UTC')::date=d.work_date),0)::integer as minutes
    from staff s cross join dates d
    where d.work_date >= s.leave_accrual_start
  ), rollup as (
    select s.id,
      (select count(*)::integer from day_facts f where f.uid=s.id and f.is_sunday) as sunday_count,
      (select count(*)::integer from day_facts f where f.uid=s.id and f.is_holiday and not f.is_sunday) as holiday_count,
      (select coalesce(sum(private.attendance_day_credit(s.id,f.work_date)),0)::numeric from day_facts f where f.uid=s.id and f.has_session and not f.is_sunday and not f.is_holiday) as worked_day_count,
      (select coalesce(sum(private.attendance_day_credit(s.id,f.work_date)),0)::numeric from day_facts f where f.uid=s.id and f.on_leave and not f.has_session and not f.is_sunday and not f.is_holiday) as leave_day_count,
      (select coalesce(sum(private.attendance_day_credit(s.id,f.work_date)),0)::numeric from day_facts f where f.uid=s.id and not f.is_sunday and not f.is_holiday) as scheduled_count,
      (select coalesce(sum(f.minutes),0)::integer from day_facts f where f.uid=s.id) as work_minutes,
      (select coalesce(jsonb_agg(jsonb_build_object(
        'date', f.work_date,
        'status', case when f.is_sunday then 'WO' when f.is_holiday then 'PH' when f.has_session then 'P' when f.on_leave then 'L' else 'A' end,
        'punch_in', f.punch_in, 'punch_out', f.punch_out,
        'worked_minutes', f.minutes, 'holiday_name', f.holiday_name, 'leave_type', f.leave_type,
        'credited_days', case when f.is_sunday or f.is_holiday then 1::numeric when f.has_session or f.on_leave then private.attendance_day_credit(s.id,f.work_date) else 0::numeric end,
        'saturday_full_day_credit', s.saturday_full_day_credit and extract(dow from f.work_date)::integer=6 and f.has_session
      ) order by f.work_date), '[]'::jsonb) from day_facts f where f.uid=s.id) as days
    from staff s
  )
  select s.id, s.employee_id, s.display_name, s.saturday_full_day_credit,
    (r.sunday_count + r.holiday_count + r.worked_day_count)::numeric,
    r.leave_day_count,
    greatest(0::numeric, r.scheduled_count-r.worked_day_count-r.leave_day_count)::numeric,
    r.holiday_count, r.work_minutes,
    private.paid_leave_balance_for(s.id, current_date),
    s.leave_accrual_start, s.leave_opening_balance, r.days
  from staff s join rollup r on r.id=s.id
  order by s.display_name, s.employee_id;
end;
$function$;
revoke all on function public.admin_attendance_report(date) from public, anon;
grant execute on function public.admin_attendance_report(date) to authenticated;

create or replace function private.admin_update_attendance_settings_impl(
  p_user_id uuid, p_saturday_full_day_credit boolean,
  p_leave_accrual_start date, p_leave_opening_balance numeric
)
returns void
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
begin
  if not private.is_admin() then raise exception 'Only an Admin can edit employee attendance settings.' using errcode='42501'; end if;
  if p_leave_accrual_start is null or p_leave_opening_balance < 0 then
    raise exception 'Leave settings are outside the allowed range.' using errcode='22023';
  end if;
  update public.profiles set
    saturday_full_day_credit=p_saturday_full_day_credit,
    leave_accrual_start=date_trunc('month',p_leave_accrual_start)::date,
    leave_opening_balance=p_leave_opening_balance
  where id=p_user_id;
  if not found then raise exception 'Employee was not found.' using errcode='P0002'; end if;
end;
$function$;
revoke all on function private.admin_update_attendance_settings_impl(uuid,boolean,date,numeric) from public, anon;
grant execute on function private.admin_update_attendance_settings_impl(uuid,boolean,date,numeric) to authenticated;

create or replace function public.admin_update_attendance_settings(
  p_user_id uuid, p_saturday_full_day_credit boolean,
  p_leave_accrual_start date, p_leave_opening_balance numeric
)
returns void language sql security invoker
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
as $function$
  select private.admin_update_attendance_settings_impl(p_user_id,p_saturday_full_day_credit,p_leave_accrual_start,p_leave_opening_balance)
$function$;
revoke all on function public.admin_update_attendance_settings(uuid,boolean,date,numeric) from public, anon;
grant execute on function public.admin_update_attendance_settings(uuid,boolean,date,numeric) to authenticated;

create or replace function private.admin_import_paid_holidays_impl(p_holidays jsonb)
returns integer
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare item jsonb; saved integer := 0; d date; n text; days numeric;
begin
  if not private.is_admin() then raise exception 'Only an Admin can import paid holidays.' using errcode='42501'; end if;
  if jsonb_typeof(p_holidays) <> 'array' or jsonb_array_length(p_holidays)>500 then
    raise exception 'Upload a holiday sheet with no more than 500 rows.' using errcode='22023';
  end if;
  for item in select value from jsonb_array_elements(p_holidays) loop
    d := (item->>'date')::date;
    n := trim(item->>'name');
    days := coalesce(nullif(item->>'paid_days','')::numeric,1);
    if n is null or length(n) not between 1 and 120 or days<>1 then
      raise exception 'Each holiday needs a name; paid holidays are full-day calendar entries.' using errcode='22023';
    end if;
    insert into public.paid_holidays(holiday_date,name,paid_days,created_by)
    values(d,n,days,auth.uid())
    on conflict (holiday_date) do update set name=excluded.name, paid_days=excluded.paid_days;
    saved := saved+1;
  end loop;
  return saved;
end;
$function$;
revoke all on function private.admin_import_paid_holidays_impl(jsonb) from public, anon;
grant execute on function private.admin_import_paid_holidays_impl(jsonb) to authenticated;

create or replace function public.admin_import_paid_holidays(p_holidays jsonb)
returns integer language sql security invoker
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
as $function$ select private.admin_import_paid_holidays_impl(p_holidays) $function$;
revoke all on function public.admin_import_paid_holidays(jsonb) from public, anon;
grant execute on function public.admin_import_paid_holidays(jsonb) to authenticated;

create or replace function private.admin_private_request_reasons_impl()
returns jsonb
language plpgsql stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
begin
  if not private.is_admin() then raise exception 'Only an Admin can read request reasons.' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id',r.id,'kind','leave','reason',r.reason))
    from public.leave_requests r
  ),'[]'::jsonb) || coalesce((
    select jsonb_agg(jsonb_build_object('id',r.id,'kind','correction','reason',r.reason))
    from public.attendance_correction_requests r
  ),'[]'::jsonb);
end;
$function$;
revoke all on function private.admin_private_request_reasons_impl() from public, anon;
grant execute on function private.admin_private_request_reasons_impl() to authenticated;

create or replace function public.admin_private_request_reasons()
returns jsonb language sql security invoker
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
as $function$ select private.admin_private_request_reasons_impl() $function$;
revoke all on function public.admin_private_request_reasons() from public, anon;
grant execute on function public.admin_private_request_reasons() to authenticated;

create or replace function private.enforce_paid_leave_balance()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare available numeric;
begin
  if new.status='approved' and new.leave_type='annual'
    and (tg_op='INSERT' or (tg_op='UPDATE' and old.status is distinct from 'approved')) then
    perform 1 from public.profiles where id=new.user_id for update;
    available := private.paid_leave_balance_for(new.user_id,current_date);
    if private.workday_count(new.user_id,new.start_date,new.end_date)>available then
      raise exception 'Not enough paid leave balance. Available: % day(s).', available using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function private.enforce_paid_leave_balance() from public, anon, authenticated;
drop trigger if exists enforce_paid_leave_balance on public.leave_requests;
create trigger enforce_paid_leave_balance before insert or update of status on public.leave_requests
for each row execute function private.enforce_paid_leave_balance();

-- Request descriptions are private HR data. All signed-in users may see request
-- metadata, but only the Admin RPC above returns reason text.
revoke select on public.leave_requests from authenticated;
grant select (id,user_id,leave_type,start_date,end_date,status,review_comment,reviewed_by,reviewed_at,created_at)
  on public.leave_requests to authenticated;
revoke select on public.attendance_correction_requests from authenticated;
grant select (id,user_id,event_date,requested_in,requested_out,request_type,status,review_comment,reviewed_by,reviewed_at,created_at,updated_at)
  on public.attendance_correction_requests to authenticated;
