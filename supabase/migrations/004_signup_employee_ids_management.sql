-- INDETAIL account IDs, self-service signup/login support, and scoped manager access.

create sequence if not exists private.employee_id_seq as bigint start with 1 increment by 1 minvalue 1 maxvalue 9999;

alter table public.profiles add column if not exists employee_id text;

do $$
declare
  profile_count bigint;
begin
  select count(*) into profile_count from public.profiles where employee_id is null;
  if profile_count > 9999 then
    raise exception 'INDETAIL employee IDs have a four-digit capacity of 9,999 accounts.';
  end if;

  with numbered as (
    select id, row_number() over (order by created_at, id) as ordinal
    from public.profiles where employee_id is null
  )
  update public.profiles p
     set employee_id = 'ids' || lpad(numbered.ordinal::text, 4, '0')
    from numbered where p.id = numbered.id;
end;
$$;

create unique index if not exists profiles_employee_id_unique on public.profiles(employee_id);
alter table public.profiles alter column employee_id set not null;
alter table public.profiles add constraint profiles_employee_id_format
  check (employee_id ~ '^ids[0-9]{4}$');

select setval(
  'private.employee_id_seq',
  greatest(coalesce(max(substring(employee_id from 4)::integer), 1), 1),
  count(*) > 0
)
from public.profiles;

create or replace function private.allocate_employee_id()
returns text
language plpgsql
volatile
security definer
set search_path = pg_catalog, private, pg_temp
as $$
declare
  next_id bigint;
begin
  next_id := nextval('private.employee_id_seq');
  if next_id > 9999 then
    raise exception 'INDETAIL employee ID capacity is full.';
  end if;
  return 'ids' || lpad(next_id::text, 4, '0');
end;
$$;

alter table public.profiles alter column employee_id set default private.allocate_employee_id();

create or replace function private.create_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
begin
  insert into public.profiles (id, email, display_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), '')
  ) on conflict (id) do nothing;
  return new;
end;
$$;

create or replace function private.keep_employee_id_immutable()
returns trigger
language plpgsql
set search_path = pg_catalog, pg_temp
as $$
begin
  if new.employee_id is distinct from old.employee_id then
    raise exception 'Employee IDs cannot be changed.';
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_employee_id_immutable on public.profiles;
create trigger profiles_employee_id_immutable
before update of employee_id on public.profiles
for each row execute function private.keep_employee_id_immutable();

create or replace function private.can_manage_team(target_team uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
  select private.is_admin() or (
    private.current_app_role() = 'team_leader'::public.app_role
    and exists (
      select 1 from public.team_members tm
      where tm.team_id = target_team
        and tm.user_id = (select auth.uid())
        and tm.member_role = 'leader'
    )
  )
$$;

create or replace function private.can_manage_project(target_project uuid)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
  select private.is_admin() or (
    private.current_app_role() = 'team_leader'::public.app_role
    and exists (
      select 1 from public.projects p
      where p.id = target_project
        and p.team_id is not null
        and private.can_manage_team(p.team_id)
    )
  )
$$;

-- A manager-only directory provides employee IDs without exposing email addresses.
create or replace function public.employee_directory()
returns table(id uuid, employee_id text, display_name text, role public.app_role, is_active boolean)
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
declare
  caller_role public.app_role := private.current_app_role();
begin
  if caller_role is null then
    raise exception 'Sign in to view the employee directory.' using errcode = '42501';
  end if;

  if caller_role = 'admin'::public.app_role or (
    caller_role = 'team_leader'::public.app_role and exists (
      select 1 from public.team_members tm
      where tm.user_id = (select auth.uid()) and tm.member_role = 'leader'
    )
  ) then
    return query
      select p.id, p.employee_id, p.display_name, p.role, p.is_active
      from public.profiles p
      where p.is_active and p.role <> 'admin'::public.app_role
      order by p.display_name, p.employee_id;
  else
    return query
      select p.id, p.employee_id, p.display_name, p.role, p.is_active
      from public.profiles p
      where p.id = (select auth.uid()) and p.is_active;
  end if;
end;
$$;

-- Both roles may create teams. A Team Leader always leads the team they create.
create or replace function public.create_team(
  p_name text,
  p_description text default '',
  p_leader_id uuid default null,
  p_member_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
declare
  caller_id uuid := auth.uid();
  caller_role public.app_role := private.current_app_role();
  leader_id uuid;
  new_team_id uuid;
  target_id uuid;
begin
  if caller_id is null or caller_role is null or caller_role not in ('admin'::public.app_role, 'team_leader'::public.app_role) then
    raise exception 'Only an Admin or Team Leader can create a team.' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_name, ''))) not between 1 and 100 then
    raise exception 'Team name must contain 1 to 100 characters.' using errcode = '22023';
  end if;
  if cardinality(coalesce(p_member_ids, '{}'::uuid[])) > 200 then
    raise exception 'A team can add at most 200 members at a time.' using errcode = '22023';
  end if;

  leader_id := case when caller_role = 'team_leader'::public.app_role then caller_id else p_leader_id end;
  if leader_id is not null and not exists (
    select 1 from public.profiles p
    where p.id = leader_id and p.is_active and p.role <> 'admin'::public.app_role
  ) then
    raise exception 'Choose an active non-Admin Team Leader.' using errcode = '22023';
  end if;

  if exists (
    select 1 from unnest(coalesce(p_member_ids, '{}'::uuid[])) requested(id)
    left join public.profiles p on p.id = requested.id
    where p.id is null or not p.is_active or p.role = 'admin'::public.app_role
  ) then
    raise exception 'Only active non-Admin employees can be added to a team.' using errcode = '22023';
  end if;

  insert into public.teams(name, description, created_by)
  values (btrim(p_name), coalesce(p_description, ''), caller_id)
  returning id into new_team_id;

  foreach target_id in array coalesce(p_member_ids, '{}'::uuid[]) loop
    insert into public.team_members(team_id, user_id, member_role)
    values (new_team_id, target_id, 'member') on conflict (team_id, user_id) do nothing;
  end loop;

  if leader_id is not null then
    if caller_role = 'admin'::public.app_role then
      update public.profiles set role = 'team_leader'::public.app_role
      where id = leader_id and role = 'employee'::public.app_role;
    end if;
    insert into public.team_members(team_id, user_id, member_role)
    values (new_team_id, leader_id, 'leader')
    on conflict (team_id, user_id) do update set member_role = 'leader';
  end if;

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (caller_id, 'team.created', 'teams', new_team_id::text,
    jsonb_build_object('member_count', cardinality(coalesce(p_member_ids, '{}'::uuid[])), 'leader_assigned', leader_id is not null));
  return new_team_id;
end;
$$;

-- Members can be added later; an Admin may assign/promote a Team Leader atomically.
create or replace function public.manage_team_members(
  p_team_id uuid,
  p_member_ids uuid[] default '{}',
  p_leader_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
declare
  caller_id uuid := auth.uid();
  caller_role public.app_role := private.current_app_role();
  target_id uuid;
  prior_leader uuid;
begin
  if caller_id is null or not private.can_manage_team(p_team_id) then
    raise exception 'You do not manage this team.' using errcode = '42501';
  end if;
  if cardinality(coalesce(p_member_ids, '{}'::uuid[])) > 200 then
    raise exception 'A team can add at most 200 members at a time.' using errcode = '22023';
  end if;
  if caller_role = 'team_leader'::public.app_role and p_leader_id is not null and p_leader_id <> caller_id then
    raise exception 'A Team Leader cannot replace the team leader.' using errcode = '42501';
  end if;
  if p_leader_id is not null and not exists (
    select 1 from public.profiles p
    where p.id = p_leader_id and p.is_active and p.role <> 'admin'::public.app_role
  ) then
    raise exception 'Choose an active non-Admin Team Leader.' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_member_ids, '{}'::uuid[])) requested(id)
    left join public.profiles p on p.id = requested.id
    where p.id is null or not p.is_active or p.role = 'admin'::public.app_role
  ) then
    raise exception 'Only active non-Admin employees can be added to a team.' using errcode = '22023';
  end if;

  foreach target_id in array coalesce(p_member_ids, '{}'::uuid[]) loop
    insert into public.team_members(team_id, user_id, member_role)
    values (p_team_id, target_id, 'member') on conflict (team_id, user_id) do nothing;
  end loop;

  if p_leader_id is not null and caller_role = 'admin'::public.app_role then
    select user_id into prior_leader from public.team_members
    where team_id = p_team_id and member_role = 'leader' for update;
    if prior_leader is not null and prior_leader <> p_leader_id then
      update public.team_members set member_role = 'member'
      where team_id = p_team_id and user_id = prior_leader;
    end if;
    update public.profiles set role = 'team_leader'::public.app_role
    where id = p_leader_id and role = 'employee'::public.app_role;
    insert into public.team_members(team_id, user_id, member_role)
    values (p_team_id, p_leader_id, 'leader')
    on conflict (team_id, user_id) do update set member_role = 'leader';
  elsif caller_role = 'team_leader'::public.app_role then
    insert into public.team_members(team_id, user_id, member_role)
    values (p_team_id, caller_id, 'leader')
    on conflict (team_id, user_id) do update set member_role = 'leader';
  end if;

  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (caller_id, 'team.members_updated', 'teams', p_team_id::text,
    jsonb_build_object('member_count_added', cardinality(coalesce(p_member_ids, '{}'::uuid[])), 'leader_changed', p_leader_id is not null));
end;
$$;

-- Rate-limit public employee-ID login without storing IPs, IDs, emails, or passwords.
create table if not exists private.auth_rate_limit_buckets (
  bucket_key text primary key,
  window_started_at timestamptz not null,
  attempts integer not null check (attempts > 0)
);
revoke all on table private.auth_rate_limit_buckets from public, anon, authenticated, service_role;

create or replace function public.consume_employee_auth_attempts(
  p_bucket_keys text[],
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog, private, pg_temp
as $$
declare
  key text;
  attempt_count integer;
  all_allowed boolean := true;
begin
  if cardinality(p_bucket_keys) not between 1 and 2
     or p_limit not between 1 and 20
     or p_window_seconds not between 30 and 3600
     or exists (select 1 from unnest(p_bucket_keys) k where length(k) > 140 or k !~ '^[a-z0-9:_-]+$') then
    raise exception 'Invalid rate-limit request.' using errcode = '22023';
  end if;

  foreach key in array p_bucket_keys loop
    insert into private.auth_rate_limit_buckets(bucket_key, window_started_at, attempts)
    values (key, clock_timestamp(), 1)
    on conflict (bucket_key) do update
      set window_started_at = case
            when private.auth_rate_limit_buckets.window_started_at <= clock_timestamp() - make_interval(secs => p_window_seconds)
              then clock_timestamp()
            else private.auth_rate_limit_buckets.window_started_at
          end,
          attempts = case
            when private.auth_rate_limit_buckets.window_started_at <= clock_timestamp() - make_interval(secs => p_window_seconds)
              then 1
            else private.auth_rate_limit_buckets.attempts + 1
          end
    returning attempts into attempt_count;
    if attempt_count > p_limit then all_allowed := false; end if;
  end loop;

  delete from private.auth_rate_limit_buckets
  where window_started_at < clock_timestamp() - interval '1 day';
  return all_allowed;
end;
$$;

-- Rebuild manager policies so Team Leaders can manage only teams/projects they lead.
drop policy if exists teams_insert_admin on public.teams;
drop policy if exists teams_read_scoped on public.teams;
create policy teams_read_scoped on public.teams for select to authenticated
using ((select private.is_admin()) or exists (
  select 1 from public.team_members tm
  where tm.team_id = teams.id and tm.user_id = (select auth.uid())
));
drop policy if exists teams_update_admin on public.teams;
create policy teams_update_managers on public.teams for update to authenticated
using ((select private.can_manage_team(id)))
with check ((select private.can_manage_team(id)));
drop policy if exists teams_delete_admin on public.teams;
create policy teams_delete_managers on public.teams for delete to authenticated
using ((select private.can_manage_team(id)));

drop policy if exists team_members_insert_admin on public.team_members;
drop policy if exists team_members_update_admin on public.team_members;
drop policy if exists team_members_delete_admin on public.team_members;
revoke insert, update, delete on public.teams, public.team_members from authenticated;

drop policy if exists projects_insert_managers on public.projects;
create policy projects_insert_managers on public.projects for insert to authenticated
with check (
  created_by = (select auth.uid())
  and ((select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and team_id is not null and (select private.can_manage_team(team_id))
  ))
);
drop policy if exists projects_update_managers on public.projects;
create policy projects_update_managers on public.projects for update to authenticated
using ((select private.can_manage_project(id)))
with check ((select private.can_manage_project(id)));
drop policy if exists projects_delete_admin on public.projects;
create policy projects_delete_managers on public.projects for delete to authenticated
using ((select private.can_manage_project(id)));

drop policy if exists project_assignments_insert_scoped on public.project_assignments;
create policy project_assignments_insert_scoped on public.project_assignments for insert to authenticated
with check (
  assigned_by = (select auth.uid())
  and ((select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (select private.can_manage_project(project_id))
    and (select private.can_assign_to_user(user_id, project_id))
  ))
);
drop policy if exists project_assignments_delete_scoped on public.project_assignments;
create policy project_assignments_delete_scoped on public.project_assignments for delete to authenticated
using (
  (select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (select private.can_manage_project(project_id))
    and (select private.can_assign_to_user(user_id, project_id))
  )
);

drop policy if exists tasks_insert_managers on public.tasks;
create policy tasks_insert_managers on public.tasks for insert to authenticated
with check (
  ((select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (select private.can_manage_project(project_id))
  ))
  and ((assignee_id is null) or (select private.can_assign_to_user(assignee_id, project_id)))
);
drop policy if exists tasks_delete_managers on public.tasks;
create policy tasks_delete_managers on public.tasks for delete to authenticated
using ((select private.is_admin()) or (
  (select private.current_app_role()) = 'team_leader'::public.app_role
  and (select private.can_manage_project(project_id))
));
drop policy if exists tasks_update_scoped on public.tasks;
create policy tasks_update_scoped on public.tasks for update to authenticated
using (
  (select private.is_admin()) or assignee_id = (select auth.uid()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (select private.can_manage_project(project_id))
  )
)
with check (
  (select private.is_admin()) or assignee_id = (select auth.uid()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (select private.can_manage_project(project_id))
  )
);

drop policy if exists task_assignments_insert_scoped on public.task_assignments;
create policy task_assignments_insert_scoped on public.task_assignments for insert to authenticated
with check (
  assigned_by = (select auth.uid())
  and ((select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and exists (
      select 1 from public.tasks t
      where t.id = task_id and (select private.can_manage_project(t.project_id))
        and (select private.can_assign_to_user(user_id, t.project_id))
    )
  ))
);
drop policy if exists task_assignments_delete_scoped on public.task_assignments;
create policy task_assignments_delete_scoped on public.task_assignments for delete to authenticated
using (
  (select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and exists (
      select 1 from public.tasks t
      where t.id = task_id and (select private.can_manage_project(t.project_id))
        and (select private.can_assign_to_user(user_id, t.project_id))
    )
  )
);

drop policy if exists attendance_sites_insert_admin on public.attendance_sites;
create policy attendance_sites_insert_managers on public.attendance_sites for insert to authenticated
with check (
  created_by = (select auth.uid())
  and ((select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (kind = 'office' or (kind = 'project' and project_id is not null and (select private.can_manage_project(project_id))))
  ))
);
drop policy if exists attendance_sites_update_admin on public.attendance_sites;
create policy attendance_sites_update_managers on public.attendance_sites for update to authenticated
using (
  (select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (kind = 'office' or (kind = 'project' and project_id is not null and (select private.can_manage_project(project_id))))
  )
)
with check (
  (select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (kind = 'office' or (kind = 'project' and project_id is not null and (select private.can_manage_project(project_id))))
  )
);
drop policy if exists attendance_sites_delete_admin on public.attendance_sites;
create policy attendance_sites_delete_managers on public.attendance_sites for delete to authenticated
using (
  (select private.is_admin()) or (
    (select private.current_app_role()) = 'team_leader'::public.app_role
    and (kind = 'office' or (kind = 'project' and project_id is not null and (select private.can_manage_project(project_id))))
  )
);
drop policy if exists attendance_sites_read_assigned on public.attendance_sites;
create policy attendance_sites_read_assigned on public.attendance_sites for select to authenticated
using (
  (select private.is_admin())
  or (is_active and kind = 'office')
  or (is_active and kind = 'project' and (select private.can_access_project(project_id)))
);

-- Team members can use their team's project-site geofence as well as assigned employees.
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
    elsif site.kind = 'project' and not private.can_access_project(site.project_id) then rejection := 'You are not assigned to this project site.';
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

-- Restrict new manager and signup APIs to authenticated callers or the server-only service role.
revoke all on function private.allocate_employee_id() from public, anon, authenticated;
revoke all on function private.keep_employee_id_immutable() from public, anon, authenticated;
revoke all on function private.can_manage_team(uuid) from public, anon, authenticated;
revoke all on function private.can_manage_project(uuid) from public, anon, authenticated;
grant execute on function private.can_manage_team(uuid) to authenticated;
grant execute on function private.can_manage_project(uuid) to authenticated;

revoke all on function public.employee_directory() from public, anon;
grant execute on function public.employee_directory() to authenticated;
revoke all on function public.create_team(text, text, uuid, uuid[]) from public, anon;
grant execute on function public.create_team(text, text, uuid, uuid[]) to authenticated;
revoke all on function public.manage_team_members(uuid, uuid[], uuid) from public, anon;
grant execute on function public.manage_team_members(uuid, uuid[], uuid) to authenticated;
revoke all on function public.consume_employee_auth_attempts(text[], integer, integer) from public, anon, authenticated;
grant execute on function public.consume_employee_auth_attempts(text[], integer, integer) to service_role;

-- Continue applying 003's least-privilege defaults for new objects in the exposed schema.
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated;

