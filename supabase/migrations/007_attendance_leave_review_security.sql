-- Keep all exposed RPCs invoker-secured, and constrain request writes to their intended workflow.
do $migration$
begin
  if to_regprocedure('public.my_attendance_summary(date)') is not null
     and to_regprocedure('private.my_attendance_summary_impl(date)') is null then
    alter function public.my_attendance_summary(date) set schema private;
    alter function private.my_attendance_summary(date) rename to my_attendance_summary_impl;
  end if;
end;
$migration$;

create or replace function public.my_attendance_summary(p_month_start date default null)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog, public, private, auth, pg_temp
as $function$
  select private.my_attendance_summary_impl(p_month_start)
$function$;

revoke all on function public.my_attendance_summary(date) from public, anon;
grant execute on function public.my_attendance_summary(date) to authenticated;
revoke all on function private.my_attendance_summary_impl(date) from public, anon;
grant execute on function private.my_attendance_summary_impl(date) to authenticated;

drop policy if exists correction_requests_insert_self on public.attendance_correction_requests;
create policy correction_requests_insert_self
on public.attendance_correction_requests for insert to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'submitted'
  and reviewed_by is null
  and reviewed_at is null
);

drop policy if exists correction_requests_review on public.attendance_correction_requests;
create policy correction_requests_review
on public.attendance_correction_requests for update to authenticated
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

revoke all privileges on table public.attendance_correction_requests from authenticated;
grant select on table public.attendance_correction_requests to authenticated;
grant insert (user_id, request_type, event_date, requested_in, requested_out, reason)
  on table public.attendance_correction_requests to authenticated;
grant update (status, review_comment, reviewed_by, reviewed_at)
  on table public.attendance_correction_requests to authenticated;

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

revoke all privileges on table public.leave_requests from authenticated;
grant select on table public.leave_requests to authenticated;
grant insert (user_id, leave_type, start_date, end_date, reason)
  on table public.leave_requests to authenticated;
grant update (status, review_comment, reviewed_by, reviewed_at)
  on table public.leave_requests to authenticated;

create index if not exists leave_requests_reviewed_by_idx
  on public.leave_requests(reviewed_by);
