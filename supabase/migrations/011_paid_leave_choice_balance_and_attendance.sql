-- Two paid leave days accrue monthly from November 2026 onward. Preserve the
-- existing one-day monthly accrual for earlier months, and let Admins adjust
-- each employee's current balance through an audited ledger.

alter table public.leave_requests
  add column if not exists use_paid_leave boolean not null default false;

-- Annual leave was the only paid leave type before the explicit choice existed.
update public.leave_requests
set use_paid_leave = true
where leave_type = 'annual' and use_paid_leave = false;

alter table public.leave_requests
  add constraint leave_requests_unpaid_not_paid_check
  check (leave_type <> 'unpaid' or not use_paid_leave);

create table if not exists public.paid_leave_balance_adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  days_delta numeric not null check (days_delta <> 0 and days_delta between -500 and 500),
  note text not null default 'Admin balance adjustment' check (length(trim(note)) between 1 and 500),
  effective_on date not null default current_date,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now()
);

create index if not exists paid_leave_balance_adjustments_user_date_idx
  on public.paid_leave_balance_adjustments(user_id, effective_on);

alter table public.paid_leave_balance_adjustments enable row level security;
revoke all on table public.paid_leave_balance_adjustments from anon, authenticated;

drop trigger if exists audit_paid_leave_balance_adjustments
  on public.paid_leave_balance_adjustments;
create trigger audit_paid_leave_balance_adjustments
after insert or update or delete on public.paid_leave_balance_adjustments
for each row execute function private.write_audit_row();

create or replace function private.paid_leave_balance_for(
  p_user_id uuid,
  p_as_of date default current_date
)
returns numeric
language sql stable security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
  with profile_balance as (
    select profile.leave_opening_balance as opening,
      coalesce(accrual.legacy_months, 0)::numeric as legacy_months,
      coalesce(accrual.two_day_months, 0)::numeric as two_day_months
    from public.profiles profile
    cross join lateral (
      select count(*) filter (where month_start < date '2026-11-01') as legacy_months,
        count(*) filter (where month_start >= date '2026-11-01') as two_day_months
      from generate_series(
        profile.leave_accrual_start::timestamp,
        date_trunc('month', p_as_of)::timestamp,
        interval '1 month'
      ) as months(month_start)
    ) accrual
    where profile.id = p_user_id and profile.is_active
  ), adjustments as (
    select coalesce(sum(adjustment.days_delta), 0)::numeric as days
    from public.paid_leave_balance_adjustments adjustment
    where adjustment.user_id = p_user_id
      and adjustment.effective_on <= p_as_of
  ), consumed as (
    select coalesce(sum(private.attendance_day_credit(p_user_id, leave_day.work_date)), 0)::numeric as days
    from (
      select distinct calendar.value::date as work_date
      from public.leave_requests request
      cross join lateral generate_series(
        request.start_date::timestamp,
        least(request.end_date, p_as_of)::timestamp,
        interval '1 day'
      ) as calendar(value)
      where request.user_id = p_user_id
        and request.status = 'approved'
        and request.use_paid_leave
        and request.leave_type <> 'unpaid'
        and request.start_date <= p_as_of
        and extract(dow from calendar.value)::integer <> 0
        and not exists (
          select 1 from public.paid_holidays holiday
          where holiday.holiday_date = calendar.value::date
        )
        and not exists (
          select 1 from public.attendance_sessions session
          where session.user_id = p_user_id
            and (session.started_at at time zone 'UTC')::date = calendar.value::date
        )
        and not exists (
          select 1 from public.attendance_correction_requests correction
          where correction.user_id = p_user_id
            and correction.status = 'approved'
            and correction.event_date = calendar.value::date
        )
    ) leave_day
  )
  select greatest(
    0,
    coalesce(profile_balance.opening, 0)
      + coalesce(profile_balance.legacy_months, 0)
      + coalesce(profile_balance.two_day_months, 0) * 2
      + adjustments.days
      - consumed.days
  )::numeric
  from profile_balance cross join adjustments cross join consumed
$function$;
revoke all on function private.paid_leave_balance_for(uuid, date) from public, anon, authenticated;

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
  absent_days numeric;
  scheduled_days numeric;
  holiday_days integer;
  worked_minutes integer;
  saturday_full_day_credit boolean;
begin
  if uid is null then
    raise exception 'Sign in to view attendance totals.' using errcode = '28000';
  end if;
  month_end := (month_start + interval '1 month')::date;
  select leave_accrual_start, profiles.saturday_full_day_credit
  into employment_start, saturday_full_day_credit
  from public.profiles where id = uid;

  with credited_days as (
    select day.value::date as work_date, 1::numeric as credit
    from generate_series(greatest(month_start, employment_start)::timestamp,
        least(month_end - 1, current_date)::timestamp, interval '1 day') day(value)
    where extract(dow from day.value)::integer = 0
    union
    select holiday.holiday_date, 1::numeric
    from public.paid_holidays holiday
    where holiday.holiday_date >= month_start and holiday.holiday_date < month_end
      and holiday.holiday_date <= current_date and holiday.holiday_date >= employment_start
      and extract(dow from holiday.holiday_date)::integer <> 0
    union
    select distinct (session.started_at at time zone 'UTC')::date,
      private.attendance_day_credit(uid, (session.started_at at time zone 'UTC')::date)
    from public.attendance_sessions session
    where session.user_id = uid
      and (session.started_at at time zone 'UTC')::date >= greatest(month_start, employment_start)
      and (session.started_at at time zone 'UTC')::date < month_end
      and (session.started_at at time zone 'UTC')::date <= current_date
      and extract(dow from session.started_at at time zone 'UTC')::integer <> 0
      and not exists (select 1 from public.paid_holidays h where h.holiday_date = (session.started_at at time zone 'UTC')::date)
    union
    select correction.event_date, private.attendance_day_credit(uid, correction.event_date)
    from public.attendance_correction_requests correction
    where correction.user_id = uid and correction.status = 'approved'
      and correction.event_date >= greatest(month_start, employment_start)
      and correction.event_date < month_end and correction.event_date <= current_date
      and extract(dow from correction.event_date)::integer <> 0
      and not exists (select 1 from public.paid_holidays h where h.holiday_date = correction.event_date)
    union
    select distinct calendar.value::date,
      private.attendance_day_credit(uid, calendar.value::date)
    from public.leave_requests request
    cross join lateral generate_series(
      greatest(request.start_date, month_start)::timestamp,
      least(request.end_date, month_end - 1, current_date)::timestamp,
      interval '1 day'
    ) calendar(value)
    where request.user_id = uid and request.status = 'approved'
      and request.use_paid_leave
      and request.start_date < month_end and request.end_date >= month_start
      and calendar.value::date >= employment_start
      and extract(dow from calendar.value)::integer <> 0
      and not exists (select 1 from public.paid_holidays h where h.holiday_date = calendar.value::date)
      and not exists (
        select 1 from public.attendance_sessions session
        where session.user_id = uid
          and (session.started_at at time zone 'UTC')::date = calendar.value::date
      )
      and not exists (
        select 1 from public.attendance_correction_requests correction
        where correction.user_id = uid and correction.status = 'approved'
          and correction.event_date = calendar.value::date
      )
  )
  select coalesce(sum(credit), 0)::numeric into present_days from credited_days;

  select coalesce(sum(private.attendance_day_credit(uid, leave_day.work_date)), 0)::numeric
  into leave_days
  from (
    select distinct calendar.value::date as work_date
    from public.leave_requests request
    cross join lateral generate_series(
      greatest(request.start_date, month_start)::timestamp,
      least(request.end_date, month_end - 1, current_date)::timestamp,
      interval '1 day'
    ) calendar(value)
    where request.user_id = uid and request.status = 'approved'
      and request.start_date < month_end and request.end_date >= month_start
      and calendar.value::date >= employment_start
  ) leave_day;

  select coalesce(sum(case
      when extract(dow from day.value)::integer = 0 then 1::numeric
      when exists (select 1 from public.paid_holidays h where h.holiday_date = day.value::date) then 1::numeric
      else private.attendance_day_credit(uid, day.value::date)
    end), 0)::numeric
  into scheduled_days
  from generate_series(greatest(month_start, employment_start)::timestamp,
      least(month_end - 1, current_date)::timestamp, interval '1 day') day(value);
  absent_days := greatest(0, scheduled_days - present_days);

  select count(*)::integer into holiday_days from public.paid_holidays holiday
  where holiday.holiday_date >= month_start and holiday.holiday_date < month_end
    and holiday.holiday_date <= current_date and holiday.holiday_date >= employment_start
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
    'absent_days', coalesce(absent_days, 0),
    'paid_holiday_days', coalesce(holiday_days, 0),
    'worked_minutes', coalesce(worked_minutes, 0),
    'paid_leave_balance', private.paid_leave_balance_for(uid, current_date),
    'monthly_paid_leave_accrual', 2,
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
    select day.value::date as work_date
    from generate_series(month_start::timestamp, least(month_end - 1, current_date)::timestamp, interval '1 day') day(value)
  ), staff as (
    select p.id, p.employee_id, p.display_name, p.saturday_full_day_credit,
      p.leave_accrual_start, p.leave_opening_balance
    from public.profiles p where p.is_active
  ), day_facts as (
    select s.id as uid, d.work_date,
      exists(select 1 from public.paid_holidays h where h.holiday_date = d.work_date) as is_holiday,
      extract(dow from d.work_date)::integer = 0 as is_sunday,
      exists(select 1 from public.attendance_sessions a where a.user_id=s.id and (a.started_at at time zone 'UTC')::date=d.work_date) as has_session,
      exists(select 1 from public.attendance_correction_requests c where c.user_id=s.id and c.status='approved' and c.event_date=d.work_date) as has_correction,
      exists(select 1 from public.leave_requests l where l.user_id=s.id and l.status='approved' and l.start_date<=d.work_date and l.end_date>=d.work_date) as on_leave,
      exists(select 1 from public.leave_requests l where l.user_id=s.id and l.status='approved' and l.use_paid_leave and l.start_date<=d.work_date and l.end_date>=d.work_date) as is_paid_leave,
      coalesce(
        (select min(e.created_at) from public.attendance_events e where e.user_id=s.id and (e.created_at at time zone 'UTC')::date=d.work_date and e.action='in'),
        (select min(c.requested_in) from public.attendance_correction_requests c where c.user_id=s.id and c.status='approved' and c.event_date=d.work_date)
      ) as punch_in,
      coalesce(
        (select max(e.created_at) from public.attendance_events e where e.user_id=s.id and (e.created_at at time zone 'UTC')::date=d.work_date and e.action='out'),
        (select max(c.requested_out) from public.attendance_correction_requests c where c.user_id=s.id and c.status='approved' and c.event_date=d.work_date)
      ) as punch_out,
      (select h.name from public.paid_holidays h where h.holiday_date=d.work_date limit 1) as holiday_name,
      (select l.leave_type from public.leave_requests l where l.user_id=s.id and l.status='approved' and l.start_date<=d.work_date and l.end_date>=d.work_date order by l.created_at limit 1) as leave_type,
      (select l.use_paid_leave from public.leave_requests l where l.user_id=s.id and l.status='approved' and l.start_date<=d.work_date and l.end_date>=d.work_date order by l.created_at limit 1) as use_paid_leave,
      coalesce((select sum(greatest(0, extract(epoch from (coalesce(a.ended_at, now())-a.started_at))/60)::integer) from public.attendance_sessions a where a.user_id=s.id and (a.started_at at time zone 'UTC')::date=d.work_date),0)::integer as minutes
    from staff s cross join dates d
    where d.work_date >= s.leave_accrual_start
  ), rollup as (
    select s.id,
      (select count(*)::integer from day_facts f where f.uid=s.id and f.is_sunday) as sunday_count,
      (select count(*)::integer from day_facts f where f.uid=s.id and f.is_holiday and not f.is_sunday) as holiday_count,
      (select coalesce(sum(private.attendance_day_credit(s.id,f.work_date)),0)::numeric
        from day_facts f where f.uid=s.id and (f.has_session or f.has_correction or f.is_paid_leave) and not f.is_sunday and not f.is_holiday) as present_workday_count,
      (select coalesce(sum(private.attendance_day_credit(s.id,f.work_date)),0)::numeric
        from day_facts f where f.uid=s.id and f.on_leave and not f.is_sunday and not f.is_holiday) as leave_day_count,
      (select coalesce(sum(private.attendance_day_credit(s.id,f.work_date)),0)::numeric
        from day_facts f where f.uid=s.id and not f.is_sunday and not f.is_holiday) as scheduled_count,
      (select coalesce(sum(f.minutes),0)::integer from day_facts f where f.uid=s.id) as work_minutes,
      (select coalesce(jsonb_agg(jsonb_build_object(
        'date', f.work_date,
        'status', case when f.is_sunday then 'WO' when f.is_holiday then 'PH' when f.has_session or f.has_correction or f.is_paid_leave then 'P' else 'A' end,
        'day_note', case when f.has_session or f.has_correction then null when f.is_paid_leave then 'Paid leave' when f.on_leave then 'Unpaid leave' else null end,
        'punch_in', f.punch_in, 'punch_out', f.punch_out,
        'worked_minutes', f.minutes, 'holiday_name', f.holiday_name,
        'leave_type', f.leave_type, 'use_paid_leave', coalesce(f.use_paid_leave, false),
        'paid_leave_deducted', f.is_paid_leave and not (f.has_session or f.has_correction),
        'credited_days', case when f.is_sunday or f.is_holiday then 1::numeric when f.has_session or f.has_correction or f.is_paid_leave then private.attendance_day_credit(s.id,f.work_date) else 0::numeric end,
        'saturday_full_day_credit', s.saturday_full_day_credit and extract(dow from f.work_date)::integer=6 and (f.has_session or f.has_correction or f.is_paid_leave)
      ) order by f.work_date), '[]'::jsonb) from day_facts f where f.uid=s.id) as days
    from staff s
  )
  select s.id, s.employee_id, s.display_name, s.saturday_full_day_credit,
    (r.sunday_count + r.holiday_count + r.present_workday_count)::numeric,
    r.leave_day_count,
    greatest(0::numeric, r.scheduled_count-r.present_workday_count)::numeric,
    r.holiday_count, r.work_minutes,
    private.paid_leave_balance_for(s.id, current_date),
    s.leave_accrual_start, s.leave_opening_balance, r.days
  from staff s join rollup r on r.id=s.id
  order by s.display_name, s.employee_id;
end;
$function$;
revoke all on function public.admin_attendance_report(date) from public, anon;
grant execute on function public.admin_attendance_report(date) to authenticated;

create or replace function private.admin_set_paid_leave_balance_impl(
  p_user_id uuid,
  p_balance numeric,
  p_note text default 'Admin balance adjustment'
)
returns void
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare
  current_balance numeric;
  delta numeric;
  clean_note text := coalesce(nullif(trim(p_note), ''), 'Admin balance adjustment');
begin
  if not private.is_admin() then
    raise exception 'Only an Admin can adjust paid leave balances.' using errcode='42501';
  end if;
  if p_balance is null or p_balance < 0 or p_balance > 500 or p_balance * 2 <> round(p_balance * 2) then
    raise exception 'Enter a balance from 0 to 500 days in half-day steps.' using errcode='22023';
  end if;
  if length(clean_note) > 500 then
    raise exception 'The adjustment note is too long.' using errcode='22023';
  end if;
  perform 1 from public.profiles where id = p_user_id and is_active for update;
  if not found then
    raise exception 'Active employee was not found.' using errcode='P0002';
  end if;
  current_balance := private.paid_leave_balance_for(p_user_id, current_date);
  delta := p_balance - current_balance;
  if delta <> 0 then
    insert into public.paid_leave_balance_adjustments(user_id, days_delta, note, effective_on, created_by)
    values (p_user_id, delta, clean_note, current_date, auth.uid());
  end if;
end;
$function$;
revoke all on function private.admin_set_paid_leave_balance_impl(uuid, numeric, text) from public, anon;
grant execute on function private.admin_set_paid_leave_balance_impl(uuid, numeric, text) to authenticated;

create or replace function public.admin_set_paid_leave_balance(
  p_user_id uuid,
  p_balance numeric,
  p_note text default 'Admin balance adjustment'
)
returns void
language sql security invoker
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
as $function$
  select private.admin_set_paid_leave_balance_impl(p_user_id, p_balance, p_note)
$function$;
revoke all on function public.admin_set_paid_leave_balance(uuid, numeric, text) from public, anon;
grant execute on function public.admin_set_paid_leave_balance(uuid, numeric, text) to authenticated;

create or replace function private.enforce_paid_leave_balance()
returns trigger
language plpgsql security definer
set search_path to 'pg_catalog', 'public', 'auth', 'private', 'pg_temp'
as $function$
declare
  available numeric;
begin
  if tg_op = 'INSERT' then
    if new.status = 'approved' and new.use_paid_leave and new.leave_type <> 'unpaid' then
      perform 1 from public.profiles where id = new.user_id for update;
      available := private.paid_leave_balance_for(new.user_id, current_date);
      if private.workday_count(new.user_id, new.start_date, new.end_date) > available then
        raise exception 'Not enough paid leave balance. Available: % day(s).', available using errcode='23514';
      end if;
    end if;
  elsif new.status = 'approved' and new.use_paid_leave and new.leave_type <> 'unpaid'
    and (old.status is distinct from 'approved' or old.use_paid_leave is distinct from new.use_paid_leave
      or old.start_date is distinct from new.start_date or old.end_date is distinct from new.end_date) then
    perform 1 from public.profiles where id = new.user_id for update;
    available := private.paid_leave_balance_for(new.user_id, current_date);
    if private.workday_count(new.user_id, new.start_date, new.end_date) > available then
      raise exception 'Not enough paid leave balance. Available: % day(s).', available using errcode='23514';
    end if;
  end if;
  return new;
end;
$function$;
revoke all on function private.enforce_paid_leave_balance() from public, anon, authenticated;
drop trigger if exists enforce_paid_leave_balance on public.leave_requests;
create trigger enforce_paid_leave_balance
before insert or update of status, use_paid_leave, start_date, end_date on public.leave_requests
for each row execute function private.enforce_paid_leave_balance();

-- Leave reasons stay private to Admins. The paid/unpaid choice is ordinary
-- request metadata, so signed-in users can see it with the rest of the request.
revoke all privileges on table public.leave_requests from authenticated;
grant select (id,user_id,leave_type,use_paid_leave,start_date,end_date,status,review_comment,reviewed_by,reviewed_at,created_at)
  on public.leave_requests to authenticated;
grant insert (user_id,leave_type,use_paid_leave,start_date,end_date,reason)
  on public.leave_requests to authenticated;
grant update (status,review_comment,reviewed_by,reviewed_at)
  on public.leave_requests to authenticated;

