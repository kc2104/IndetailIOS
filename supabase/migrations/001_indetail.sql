-- INDETAIL initial schema. Apply in the Supabase SQL editor as a project owner.
-- No company locations, employee records, or credentials are seeded here.

create extension if not exists pgcrypto with schema extensions;

do $$ begin
  create type public.app_role as enum ('admin', 'team_leader', 'employee');
exception when duplicate_object then null; end $$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  display_name text not null default '',
  role public.app_role not null default 'employee',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.create_profile_for_auth_user()
returns trigger language plpgsql security definer set search_path = public, auth, pg_temp as $$
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

drop trigger if exists on_auth_user_created_indetail on auth.users;
create trigger on_auth_user_created_indetail
after insert on auth.users
for each row execute function public.create_profile_for_auth_user();

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 100),
  description text not null default '',
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  member_role text not null default 'member' check (member_role in ('leader', 'member')),
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create unique index if not exists one_team_leader_per_team
  on public.team_members(team_id) where member_role = 'leader';

create table if not exists public.projects (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 160),
  category text not null default 'Project',
  description text not null default '',
  status text not null default 'active' check (status in ('active', 'on_hold', 'completed', 'archived')),
  progress numeric(5,4) not null default 0 check (progress between 0 and 1),
  due_date date,
  team_id uuid references public.teams(id) on delete set null,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.project_assignments (
  project_id uuid not null references public.projects(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null default auth.uid() references public.profiles(id),
  assigned_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 200),
  description text not null default '',
  status text not null default 'todo' check (status in ('todo', 'in_progress', 'done', 'blocked')),
  priority text not null default 'normal' check (priority in ('low', 'normal', 'high', 'urgent')),
  assignee_id uuid references public.profiles(id) on delete set null,
  due_at timestamptz,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.task_assignments (
  task_id uuid not null references public.tasks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  assigned_by uuid not null default auth.uid() references public.profiles(id),
  assigned_at timestamptz not null default now(),
  primary key (task_id, user_id)
);

create table if not exists public.calendar_events (
  id uuid primary key default gen_random_uuid(),
  title text not null check (length(trim(title)) between 1 and 180),
  kind text not null default 'Meeting',
  description text not null default '',
  starts_at timestamptz not null,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_reports (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles(id),
  project_id uuid references public.projects(id) on delete set null,
  report_date date not null default current_date,
  completed_work text not null default '',
  in_progress_work text not null default '',
  pending_work text not null default '',
  hours_spent numeric(5,2) not null default 0 check (hours_spent between 0 and 24),
  issues text not null default '',
  tomorrow_plan text not null default '',
  status text not null default 'submitted' check (status in ('draft', 'submitted', 'under_review', 'approved', 'revision_required')),
  review_comment text not null default '',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.weekly_summaries (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles(id),
  week_start date not null,
  summary text not null,
  blockers text not null default '',
  next_week_plan text not null default '',
  status text not null default 'submitted' check (status in ('draft', 'submitted', 'under_review', 'approved', 'revision_required')),
  review_comment text not null default '',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (author_id, week_start)
);

create table if not exists public.attendance_sites (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 1 and 120),
  kind text not null check (kind in ('office', 'project')),
  project_id uuid references public.projects(id) on delete cascade,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  radius_meters integer not null default 100 check (radius_meters between 25 and 1000),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'office' and project_id is null) or (kind = 'project' and project_id is not null))
);

create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id),
  site_id uuid not null references public.attendance_sites(id),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  status text not null default 'open' check (status in ('open', 'closed')),
  created_at timestamptz not null default now(),
  check ((status = 'open' and ended_at is null) or (status = 'closed' and ended_at is not null))
);
create unique index if not exists one_open_attendance_session_per_user
  on public.attendance_sessions(user_id) where status = 'open';

create table if not exists public.attendance_events (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  site_id uuid not null references public.attendance_sites(id),
  site_name text not null,
  action text not null check (action in ('in', 'out')),
  latitude double precision not null,
  longitude double precision not null,
  accuracy_meters double precision not null,
  distance_meters double precision not null,
  risk_flag text,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_correction_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles(id),
  event_date date not null,
  requested_in timestamptz,
  requested_out timestamptz,
  reason text not null check (length(trim(reason)) between 1 and 1200),
  status text not null default 'submitted' check (status in ('submitted', 'approved', 'rejected')),
  review_comment text not null default '',
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (requested_in is not null or requested_out is not null)
);

create table if not exists public.project_photos (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects(id) on delete cascade,
  uploaded_by uuid not null default auth.uid() references public.profiles(id),
  object_path text not null unique,
  caption text not null default '',
  content_type text not null default 'image/jpeg',
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_table text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns public.app_role language sql stable security definer
set search_path = public, auth, pg_temp as $$
  select role from public.profiles where id = auth.uid() and is_active = true
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public, auth, pg_temp as $$
  select coalesce(public.current_app_role() = 'admin'::public.app_role, false)
$$;

create or replace function public.can_review_user(target_user uuid)
returns boolean language sql stable security definer
set search_path = public, auth, pg_temp as $$
  select public.is_admin() or (
    public.current_app_role() = 'team_leader'::public.app_role and exists (
      select 1 from public.team_members leader
      join public.team_members member on member.team_id = leader.team_id
      where leader.user_id = auth.uid() and leader.member_role = 'leader'
        and member.user_id = target_user
    )
  )
$$;

create or replace function public.can_access_project(target_project uuid)
returns boolean language sql stable security definer
set search_path = public, auth, pg_temp as $$
  select public.is_admin() or exists (
    select 1 from public.projects p
    where p.id = target_project and (
      p.created_by = auth.uid()
      or exists (select 1 from public.project_assignments a where a.project_id = p.id and a.user_id = auth.uid())
      or (p.team_id is not null and exists (select 1 from public.team_members tm where tm.team_id = p.team_id and tm.user_id = auth.uid()))
    )
  )
$$;

create or replace function public.can_assign_to_user(target_user uuid, target_project uuid default null)
returns boolean language plpgsql stable security definer
set search_path = public, auth, pg_temp as $$
declare
  target_team uuid;
begin
  if public.is_admin() then return true; end if;
  if public.current_app_role() <> 'team_leader'::public.app_role then return false; end if;
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

create or replace function public.haversine_meters(lat1 double precision, lon1 double precision, lat2 double precision, lon2 double precision)
returns double precision language sql immutable strict as $$
  select 6371000.0 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)
  ))
$$;

create or replace function public.write_audit_row()
returns trigger language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  row_value jsonb;
  row_id text;
  action_name text;
begin
  if tg_op = 'DELETE' then row_value := to_jsonb(old); row_id := row_value ->> 'id';
  else row_value := to_jsonb(new); row_id := row_value ->> 'id'; end if;
  action_name := lower(tg_op);
  insert into public.audit_logs(actor_id, action, entity_table, entity_id, details)
  values (
    auth.uid(), action_name, tg_table_name, row_id,
    jsonb_strip_nulls(jsonb_build_object(
      'status', row_value -> 'status',
      'role', row_value -> 'role',
      'progress', row_value -> 'progress',
      'project_id', row_value -> 'project_id',
      'team_id', row_value -> 'team_id'
    ))
  );
  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','teams','team_members','projects','project_assignments','tasks','task_assignments','calendar_events','daily_reports','weekly_summaries','attendance_sites','attendance_correction_requests','project_photos'] loop
    execute format('drop trigger if exists audit_%I on public.%I', table_name, table_name);
    execute format('create trigger audit_%I after insert or update or delete on public.%I for each row execute function public.write_audit_row()', table_name, table_name);
  end loop;
end $$;

create or replace function public.record_attendance(
  p_action text,
  p_site_id uuid,
  p_latitude double precision,
  p_longitude double precision,
  p_accuracy_meters double precision,
  p_mocked_signal boolean default false
)
returns jsonb language plpgsql security definer
set search_path = public, auth, pg_temp as $$
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
    ) and not public.is_admin() then rejection := 'You are not assigned to this project site.';
    else
      measured_distance := public.haversine_meters(p_latitude, p_longitude, site.latitude, site.longitude);
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

create index if not exists project_assignments_user_idx on public.project_assignments(user_id);
create index if not exists task_assignments_user_idx on public.task_assignments(user_id);
create index if not exists tasks_project_due_idx on public.tasks(project_id, due_at);
create index if not exists reports_author_date_idx on public.daily_reports(author_id, report_date desc);
create index if not exists attendance_user_created_idx on public.attendance_events(user_id, created_at desc);
create index if not exists correction_user_created_idx on public.attendance_correction_requests(user_id, created_at desc);

do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','teams','team_members','projects','project_assignments','tasks','task_assignments','calendar_events','daily_reports','weekly_summaries','attendance_sites','attendance_sessions','attendance_events','attendance_correction_requests','project_photos','audit_logs'] loop
    execute format('alter table public.%I enable row level security', table_name);
  end loop;
end $$;

drop policy if exists profiles_read_scoped on public.profiles;
create policy profiles_read_scoped on public.profiles for select to authenticated
using (id = auth.uid() or public.is_admin() or public.can_review_user(id));
drop policy if exists profiles_update_admin on public.profiles;
create policy profiles_update_admin on public.profiles for update to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists teams_read_scoped on public.teams;
create policy teams_read_scoped on public.teams for select to authenticated
using (public.is_admin() or exists (select 1 from public.team_members tm where tm.team_id = id and tm.user_id = auth.uid()));
drop policy if exists teams_insert_admin on public.teams;
create policy teams_insert_admin on public.teams for insert to authenticated with check (public.is_admin() and created_by = auth.uid());
drop policy if exists teams_update_admin on public.teams;
create policy teams_update_admin on public.teams for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists teams_delete_admin on public.teams;
create policy teams_delete_admin on public.teams for delete to authenticated using (public.is_admin());

drop policy if exists team_members_read_scoped on public.team_members;
create policy team_members_read_scoped on public.team_members for select to authenticated
using (public.is_admin() or user_id = auth.uid() or public.can_review_user(user_id));
drop policy if exists team_members_write_admin on public.team_members;
create policy team_members_write_admin on public.team_members for all to authenticated
using (public.is_admin()) with check (public.is_admin());

drop policy if exists projects_read_scoped on public.projects;
create policy projects_read_scoped on public.projects for select to authenticated using (public.can_access_project(id));
drop policy if exists projects_insert_managers on public.projects;
create policy projects_insert_managers on public.projects for insert to authenticated
with check (public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and exists (select 1 from public.team_members tm where tm.user_id = auth.uid() and tm.member_role = 'leader')));
drop policy if exists projects_update_managers on public.projects;
create policy projects_update_managers on public.projects for update to authenticated
using (public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and created_by = auth.uid()))
with check (public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and created_by = auth.uid()));
drop policy if exists projects_delete_admin on public.projects;
create policy projects_delete_admin on public.projects for delete to authenticated using (public.is_admin());

drop policy if exists project_assignments_read_scoped on public.project_assignments;
create policy project_assignments_read_scoped on public.project_assignments for select to authenticated using (public.can_access_project(project_id));
drop policy if exists project_assignments_insert_scoped on public.project_assignments;
create policy project_assignments_insert_scoped on public.project_assignments for insert to authenticated
with check ((public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and public.can_access_project(project_id) and public.can_assign_to_user(user_id, project_id))) and assigned_by = auth.uid());
drop policy if exists project_assignments_delete_scoped on public.project_assignments;
create policy project_assignments_delete_scoped on public.project_assignments for delete to authenticated
using (public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and public.can_access_project(project_id) and public.can_assign_to_user(user_id, project_id)));

drop policy if exists tasks_read_scoped on public.tasks;
create policy tasks_read_scoped on public.tasks for select to authenticated
using (assignee_id = auth.uid() or public.can_access_project(project_id));
drop policy if exists tasks_insert_managers on public.tasks;
create policy tasks_insert_managers on public.tasks for insert to authenticated
with check ((public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and public.can_access_project(project_id))) and (assignee_id is null or public.can_assign_to_user(assignee_id, project_id)));
drop policy if exists tasks_update_scoped on public.tasks;
create policy tasks_update_scoped on public.tasks for update to authenticated
using (public.is_admin() or assignee_id = auth.uid() or (public.current_app_role() = 'team_leader'::public.app_role and public.can_access_project(project_id)))
with check (public.is_admin() or assignee_id = auth.uid() or (public.current_app_role() = 'team_leader'::public.app_role and public.can_access_project(project_id)));
drop policy if exists tasks_delete_managers on public.tasks;
create policy tasks_delete_managers on public.tasks for delete to authenticated using (public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and public.can_access_project(project_id)));

drop policy if exists task_assignments_read_scoped on public.task_assignments;
create policy task_assignments_read_scoped on public.task_assignments for select to authenticated
using (user_id = auth.uid() or exists (select 1 from public.tasks t where t.id = task_id and public.can_access_project(t.project_id)));
drop policy if exists task_assignments_insert_scoped on public.task_assignments;
create policy task_assignments_insert_scoped on public.task_assignments for insert to authenticated
with check ((public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and exists (
  select 1 from public.tasks t where t.id = task_id and public.can_access_project(t.project_id) and public.can_assign_to_user(user_id, t.project_id)
))) and assigned_by = auth.uid());
drop policy if exists task_assignments_delete_scoped on public.task_assignments;
create policy task_assignments_delete_scoped on public.task_assignments for delete to authenticated using (public.is_admin() or (public.current_app_role() = 'team_leader'::public.app_role and exists (
  select 1 from public.tasks t where t.id = task_id and public.can_access_project(t.project_id)
)));

drop policy if exists calendar_events_read_authenticated on public.calendar_events;
create policy calendar_events_read_authenticated on public.calendar_events for select to authenticated using (true);
drop policy if exists calendar_events_write_managers on public.calendar_events;
create policy calendar_events_write_managers on public.calendar_events for all to authenticated
using (public.is_admin() or public.current_app_role() = 'team_leader'::public.app_role)
with check ((public.is_admin() or public.current_app_role() = 'team_leader'::public.app_role) and created_by = auth.uid());

drop policy if exists daily_reports_read_scoped on public.daily_reports;
create policy daily_reports_read_scoped on public.daily_reports for select to authenticated
using (author_id = auth.uid() or public.can_review_user(author_id));
drop policy if exists daily_reports_insert_self on public.daily_reports;
create policy daily_reports_insert_self on public.daily_reports for insert to authenticated
with check (author_id = auth.uid() and (project_id is null or public.can_access_project(project_id)));
drop policy if exists daily_reports_update_review on public.daily_reports;
create policy daily_reports_update_review on public.daily_reports for update to authenticated
using (public.can_review_user(author_id)) with check (public.can_review_user(author_id));

drop policy if exists weekly_summaries_read_scoped on public.weekly_summaries;
create policy weekly_summaries_read_scoped on public.weekly_summaries for select to authenticated
using (author_id = auth.uid() or public.can_review_user(author_id));
drop policy if exists weekly_summaries_insert_self on public.weekly_summaries;
create policy weekly_summaries_insert_self on public.weekly_summaries for insert to authenticated with check (author_id = auth.uid());
drop policy if exists weekly_summaries_update_review on public.weekly_summaries;
create policy weekly_summaries_update_review on public.weekly_summaries for update to authenticated
using (public.can_review_user(author_id)) with check (public.can_review_user(author_id));

drop policy if exists attendance_sites_read_assigned on public.attendance_sites;
create policy attendance_sites_read_assigned on public.attendance_sites for select to authenticated
using (public.is_admin() or (is_active and (kind = 'office' or exists (select 1 from public.project_assignments pa where pa.project_id = attendance_sites.project_id and pa.user_id = auth.uid()))));
drop policy if exists attendance_sites_write_admin on public.attendance_sites;
create policy attendance_sites_write_admin on public.attendance_sites for all to authenticated
using (public.is_admin()) with check (public.is_admin() and created_by = auth.uid());

drop policy if exists attendance_sessions_read_scoped on public.attendance_sessions;
create policy attendance_sessions_read_scoped on public.attendance_sessions for select to authenticated
using (user_id = auth.uid() or public.can_review_user(user_id));
drop policy if exists attendance_events_read_scoped on public.attendance_events;
create policy attendance_events_read_scoped on public.attendance_events for select to authenticated
using (user_id = auth.uid() or public.can_review_user(user_id));
revoke insert, update, delete on public.attendance_sessions from anon, authenticated;
revoke insert, update, delete on public.attendance_events from anon, authenticated;

drop policy if exists correction_requests_read_scoped on public.attendance_correction_requests;
create policy correction_requests_read_scoped on public.attendance_correction_requests for select to authenticated
using (user_id = auth.uid() or public.can_review_user(user_id));
drop policy if exists correction_requests_insert_self on public.attendance_correction_requests;
create policy correction_requests_insert_self on public.attendance_correction_requests for insert to authenticated with check (user_id = auth.uid());
drop policy if exists correction_requests_review on public.attendance_correction_requests;
create policy correction_requests_review on public.attendance_correction_requests for update to authenticated
using (public.can_review_user(user_id)) with check (public.can_review_user(user_id));

drop policy if exists project_photos_read_assigned on public.project_photos;
create policy project_photos_read_assigned on public.project_photos for select to authenticated using (public.can_access_project(project_id));
drop policy if exists project_photos_insert_assigned on public.project_photos;
create policy project_photos_insert_assigned on public.project_photos for insert to authenticated
with check (uploaded_by = auth.uid() and public.can_access_project(project_id));
drop policy if exists project_photos_delete_uploader_or_admin on public.project_photos;
create policy project_photos_delete_uploader_or_admin on public.project_photos for delete to authenticated
using (uploaded_by = auth.uid() or public.is_admin());

drop policy if exists audit_logs_read_scoped on public.audit_logs;
create policy audit_logs_read_scoped on public.audit_logs for select to authenticated
using (public.is_admin() or public.can_review_user(actor_id));
revoke insert, update, delete on public.audit_logs from anon, authenticated;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.can_review_user(uuid) from public, anon;
revoke all on function public.can_access_project(uuid) from public, anon;
revoke all on function public.can_assign_to_user(uuid, uuid) from public, anon;
revoke all on function public.haversine_meters(double precision, double precision, double precision, double precision) from public, anon;
revoke all on function public.record_attendance(text, uuid, double precision, double precision, double precision, boolean) from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_review_user(uuid) to authenticated;
grant execute on function public.can_access_project(uuid) to authenticated;
grant execute on function public.can_assign_to_user(uuid, uuid) to authenticated;
grant execute on function public.haversine_meters(double precision, double precision, double precision, double precision) to authenticated;
grant execute on function public.record_attendance(text, uuid, double precision, double precision, double precision, boolean) to authenticated;

grant usage on schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('project-media', 'project-media', false, 8388608, array['image/jpeg','image/png','image/webp','image/heic'])
on conflict (id) do update set public = false, file_size_limit = 8388608,
  allowed_mime_types = array['image/jpeg','image/png','image/webp','image/heic'];

drop policy if exists indetail_project_media_read on storage.objects;
create policy indetail_project_media_read on storage.objects for select to authenticated
using (bucket_id = 'project-media' and public.can_access_project((storage.foldername(name))[1]::uuid));
drop policy if exists indetail_project_media_insert on storage.objects;
create policy indetail_project_media_insert on storage.objects for insert to authenticated
with check (bucket_id = 'project-media' and public.can_access_project((storage.foldername(name))[1]::uuid));
drop policy if exists indetail_project_media_delete on storage.objects;
create policy indetail_project_media_delete on storage.objects for delete to authenticated
using (bucket_id = 'project-media' and (public.is_admin() or owner_id = auth.uid()::text));

do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','teams','projects','tasks','calendar_events','daily_reports','weekly_summaries','attendance_sites','attendance_correction_requests'] loop
    execute format('drop trigger if exists updated_at_%I on public.%I', table_name, table_name);
    execute format('create trigger updated_at_%I before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
  end loop;
end $$;

