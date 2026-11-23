-- Keep internal SECURITY DEFINER functions out of the PostgREST-exposed public schema.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

alter function public.current_app_role() set schema private;
alter function public.is_admin() set schema private;
alter function public.can_review_user(uuid) set schema private;
alter function public.can_access_project(uuid) set schema private;
alter function public.can_assign_to_user(uuid, uuid) set schema private;
alter function public.haversine_meters(double precision, double precision, double precision, double precision) set schema private;
alter function public.create_profile_for_auth_user() set schema private;
alter function public.write_audit_row() set schema private;
alter function public.record_attendance(text, uuid, double precision, double precision, double precision, boolean) set schema private;
alter function private.record_attendance(text, uuid, double precision, double precision, double precision, boolean) rename to record_attendance_impl;

create or replace function private.current_app_role()
returns public.app_role language sql stable security definer
set search_path = pg_catalog, public, auth, private, pg_temp as $$
  select p.role from public.profiles p where p.id = auth.uid() and p.is_active = true
$$;

create or replace function private.is_admin()
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth, private, pg_temp as $$
  select coalesce(private.current_app_role() = 'admin'::public.app_role, false)
$$;

create or replace function private.can_review_user(target_user uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth, private, pg_temp as $$
  select private.is_admin() or (
    private.current_app_role() = 'team_leader'::public.app_role and exists (
      select 1 from public.team_members leader
      join public.team_members member on member.team_id = leader.team_id
      where leader.user_id = auth.uid() and leader.member_role = 'leader'
        and member.user_id = target_user
    )
  )
$$;

create or replace function private.can_access_project(target_project uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public, auth, private, pg_temp as $$
  select private.is_admin() or exists (
    select 1 from public.projects p
    where p.id = target_project and (
      p.created_by = auth.uid()
      or exists (select 1 from public.project_assignments a where a.project_id = p.id and a.user_id = auth.uid())
      or (p.team_id is not null and exists (select 1 from public.team_members tm where tm.team_id = p.team_id and tm.user_id = auth.uid()))
    )
  )
$$;

create or replace function private.can_assign_to_user(target_user uuid, target_project uuid default null)
returns boolean language plpgsql stable security definer
set search_path = pg_catalog, public, auth, private, pg_temp as $$
declare
  target_team uuid;
begin
  if private.is_admin() then return true; end if;
  if private.current_app_role() <> 'team_leader'::public.app_role then return false; end if;
  if target_project is not null then
    select team_id into target_team from public.projects where id = target_project;
  end if;
  return exists (
    select 1 from public.team_members leader
    join public.team_members member on member.team_id = leader.team_id
    where leader.user_id = auth.uid() and leader.member_role = 'leader'
      and member.user_id = target_user
      and (target_team is null or target_team = leader.team_id)
  );
end;
$$;

create or replace function private.haversine_meters(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
returns double precision language sql immutable strict
set search_path = pg_catalog, pg_temp as $$
  select 6371000.0 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
  ))
$$;

create or replace function private.record_attendance_impl(
  p_action text,
  p_site_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_mocked_signal boolean default false
)
returns jsonb language plpgsql security definer
set search_path = pg_catalog, public, auth, private, pg_temp as $$
declare
  uid uuid := auth.uid();
  site public.attendance_sites%rowtype;
  active_session public.attendance_sessions%rowtype;
  measured_distance double precision;
  rejection text;
  session_id uuid;
begin
  if uid is null then return jsonb_build_object('accepted', false, 'reason', 'Sign in before recording attendance.'); end if;
  perform pg_advisory_xact_lock(hashtext(uid::text));

  if not exists (select 1 from public.profiles where id = uid and is_active = true) then rejection := 'This account is not active.';
  elsif p_action is null or p_action not in ('in', 'out') then rejection := 'Unknown attendance action.';
  elsif p_latitude is null or p_longitude is null or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then rejection := 'Location coordinates are invalid.';
  elsif p_accuracy_meters is null or p_accuracy_meters < 0 or p_accuracy_meters > 35 then rejection := 'GPS accuracy must be 35 metres or better.';
  elsif coalesce(p_mocked_signal, false) then rejection := 'A simulated device location was flagged.';
  else
    select * into site from public.attendance_sites where id = p_site_id and is_active = true;
    if not found then rejection := 'This attendance site is inactive or unavailable.';
    elsif site.kind = 'project' and not exists (
      select 1 from public.project_assignments a where a.project_id = site.project_id and a.user_id = uid
    ) and not private.is_admin() then rejection := 'You are not assigned to this project site.';
    else
      measured_distance := private.haversine_meters(p_latitude, p_longitude, site.latitude, site.longitude);
      if measured_distance > site.radius_meters then rejection := 'You are outside the approved site radius.';
      end if;
    end if;
  end if;

  if rejection is not null then
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
    values (uid, 'attendance.rejected', 'attendance_sites', p_site_id::text, jsonb_build_object(
      'reason', rejection, 'action', p_action, 'accuracy_meters', p_accuracy_meters,
      'mocked_signal', coalesce(p_mocked_signal, false)
    ));
    return jsonb_build_object('accepted', false, 'reason', rejection);
  end if;

  select * into active_session from public.attendance_sessions where user_id = uid and status = 'open' for update;
  if p_action = 'in' and active_session.id is not null then
    rejection := 'You are already punched in.';
  elsif p_action = 'out' and active_session.id is null then
    rejection := 'There is no open attendance session to punch out.';
  end if;
  if rejection is not null then
    insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
    values (uid, 'attendance.rejected', 'attendance_sessions', coalesce(active_session.id::text, ''), jsonb_build_object('reason', rejection, 'action', p_action));
    return jsonb_build_object('accepted', false, 'reason', rejection);
  end if;

  if p_action = 'in' then
    insert into public.attendance_sessions(user_id, site_id, status) values (uid, site.id, 'open') returning id into session_id;
  else
    session_id := active_session.id;
    update public.attendance_sessions set ended_at = now(), status = 'closed' where id = session_id;
  end if;

  insert into public.attendance_events(session_id, user_id, site_id, site_name, action, latitude, longitude, accuracy_meters, distance_meters, risk_flag)
  values (session_id, uid, site.id, site.name, p_action, p_latitude, p_longitude, p_accuracy_meters, measured_distance, null);
  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (uid, 'attendance.' || p_action, 'attendance_sessions', session_id::text, jsonb_build_object('site_id', site.id, 'distance_meters', round(measured_distance), 'accuracy_meters', p_accuracy_meters));
  return jsonb_build_object('accepted', true, 'session_id', session_id, 'action', p_action, 'site_name', site.name, 'distance_meters', round(measured_distance));
end;
$$;

create or replace function public.record_attendance(
  p_action text,
  p_site_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_mocked_signal boolean default false
)
returns jsonb language sql security invoker
set search_path = pg_catalog, public, private, auth, pg_temp as $$
  select private.record_attendance_impl(p_action, p_site_id, p_latitude, p_longitude, p_accuracy_meters, p_mocked_signal)
$$;

-- Replace per-row auth/helper evaluation with initplans where the result is constant for a statement.
do $$
declare
  policy_row record;
  new_qual text;
  new_check text;
begin
  for policy_row in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies where schemaname in ('public', 'storage')
  loop
    new_qual := policy_row.qual;
    new_check := policy_row.with_check;
    if new_qual is not null then
      new_qual := replace(new_qual, 'public.is_admin()', 'private.is_admin()');
      new_qual := replace(new_qual, 'public.current_app_role()', 'private.current_app_role()');
      new_qual := replace(new_qual, 'public.can_review_user(', 'private.can_review_user(');
      new_qual := replace(new_qual, 'public.can_access_project(', 'private.can_access_project(');
      new_qual := replace(new_qual, 'public.can_assign_to_user(', 'private.can_assign_to_user(');
      new_qual := replace(new_qual, 'auth.uid()', '(select auth.uid())');
      new_qual := replace(new_qual, 'private.is_admin()', '(select private.is_admin())');
      new_qual := replace(new_qual, 'private.current_app_role()', '(select private.current_app_role())');
    end if;
    if new_check is not null then
      new_check := replace(new_check, 'public.is_admin()', 'private.is_admin()');
      new_check := replace(new_check, 'public.current_app_role()', 'private.current_app_role()');
      new_check := replace(new_check, 'public.can_review_user(', 'private.can_review_user(');
      new_check := replace(new_check, 'public.can_access_project(', 'private.can_access_project(');
      new_check := replace(new_check, 'public.can_assign_to_user(', 'private.can_assign_to_user(');
      new_check := replace(new_check, 'auth.uid()', '(select auth.uid())');
      new_check := replace(new_check, 'private.is_admin()', '(select private.is_admin())');
      new_check := replace(new_check, 'private.current_app_role()', '(select private.current_app_role())');
    end if;

    if new_qual is distinct from policy_row.qual or new_check is distinct from policy_row.with_check then
      if new_qual is not null and new_check is not null then
        execute format('alter policy %I on %I.%I using (%s) with check (%s)', policy_row.policyname, policy_row.schemaname, policy_row.tablename, new_qual, new_check);
      elsif new_qual is not null then
        execute format('alter policy %I on %I.%I using (%s)', policy_row.policyname, policy_row.schemaname, policy_row.tablename, new_qual);
      elsif new_check is not null then
        execute format('alter policy %I on %I.%I with check (%s)', policy_row.policyname, policy_row.schemaname, policy_row.tablename, new_check);
      end if;
    end if;
  end loop;
end;
$$;

-- Separate write policies from read policies so SELECT is evaluated only once.
drop policy if exists team_members_write_admin on public.team_members;
create policy team_members_insert_admin on public.team_members for insert to authenticated
with check ((select private.is_admin()));
create policy team_members_update_admin on public.team_members for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()));
create policy team_members_delete_admin on public.team_members for delete to authenticated
using ((select private.is_admin()));

drop policy if exists calendar_events_write_managers on public.calendar_events;
create policy calendar_events_insert_managers on public.calendar_events for insert to authenticated
with check (((select private.is_admin()) or (select private.current_app_role()) = 'team_leader'::public.app_role) and created_by = (select auth.uid()));
create policy calendar_events_update_managers on public.calendar_events for update to authenticated
using ((select private.is_admin()) or (select private.current_app_role()) = 'team_leader'::public.app_role)
with check (((select private.is_admin()) or (select private.current_app_role()) = 'team_leader'::public.app_role) and created_by = (select auth.uid()));
create policy calendar_events_delete_managers on public.calendar_events for delete to authenticated
using ((select private.is_admin()) or (select private.current_app_role()) = 'team_leader'::public.app_role);

drop policy if exists attendance_sites_write_admin on public.attendance_sites;
create policy attendance_sites_insert_admin on public.attendance_sites for insert to authenticated
with check ((select private.is_admin()) and created_by = (select auth.uid()));
create policy attendance_sites_update_admin on public.attendance_sites for update to authenticated
using ((select private.is_admin())) with check ((select private.is_admin()) and created_by = (select auth.uid()));
create policy attendance_sites_delete_admin on public.attendance_sites for delete to authenticated
using ((select private.is_admin()));

-- Index every remaining foreign key used for scoped joins and deletes.
create index if not exists attendance_correction_reviewed_by_idx on public.attendance_correction_requests(reviewed_by);
create index if not exists attendance_events_session_id_idx on public.attendance_events(session_id);
create index if not exists attendance_events_site_id_idx on public.attendance_events(site_id);
create index if not exists attendance_sessions_site_id_idx on public.attendance_sessions(site_id);
create index if not exists attendance_sites_created_by_idx on public.attendance_sites(created_by);
create index if not exists attendance_sites_project_id_idx on public.attendance_sites(project_id);
create index if not exists audit_logs_actor_id_idx on public.audit_logs(actor_id);
create index if not exists calendar_events_created_by_idx on public.calendar_events(created_by);
create index if not exists daily_reports_project_id_idx on public.daily_reports(project_id);
create index if not exists daily_reports_reviewed_by_idx on public.daily_reports(reviewed_by);
create index if not exists project_assignments_assigned_by_idx on public.project_assignments(assigned_by);
create index if not exists project_photos_project_id_idx on public.project_photos(project_id);
create index if not exists project_photos_uploaded_by_idx on public.project_photos(uploaded_by);
create index if not exists projects_created_by_idx on public.projects(created_by);
create index if not exists projects_team_id_idx on public.projects(team_id);
create index if not exists task_assignments_assigned_by_idx on public.task_assignments(assigned_by);
create index if not exists tasks_assignee_id_idx on public.tasks(assignee_id);
create index if not exists tasks_created_by_idx on public.tasks(created_by);
create index if not exists team_members_user_id_idx on public.team_members(user_id);
create index if not exists teams_created_by_idx on public.teams(created_by);
create index if not exists weekly_summaries_reviewed_by_idx on public.weekly_summaries(reviewed_by);

-- Only authenticated users can invoke the attendance RPC. Internal helpers are unavailable as public RPCs.
revoke all on function private.current_app_role() from public, anon, authenticated;
revoke all on function private.is_admin() from public, anon, authenticated;
revoke all on function private.can_review_user(uuid) from public, anon, authenticated;
revoke all on function private.can_access_project(uuid) from public, anon, authenticated;
revoke all on function private.can_assign_to_user(uuid, uuid) from public, anon, authenticated;
revoke all on function private.haversine_meters(double precision, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function private.create_profile_for_auth_user() from public, anon, authenticated;
revoke all on function private.write_audit_row() from public, anon, authenticated;
revoke all on function private.record_attendance_impl(text, uuid, double precision, double precision, double precision, boolean) from public, anon, authenticated;
revoke all on function public.record_attendance(text, uuid, double precision, double precision, double precision, boolean) from public, anon, authenticated;

grant execute on function private.current_app_role() to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.can_review_user(uuid) to authenticated;
grant execute on function private.can_access_project(uuid) to authenticated;
grant execute on function private.can_assign_to_user(uuid, uuid) to authenticated;
grant execute on function private.record_attendance_impl(text, uuid, double precision, double precision, double precision, boolean) to authenticated;
grant execute on function public.record_attendance(text, uuid, double precision, double precision, double precision, boolean) to authenticated;
