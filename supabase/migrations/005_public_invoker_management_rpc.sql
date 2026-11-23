-- Keep manager and directory RPC endpoints invoker-security at the exposed API layer.
-- Their narrowly checked SECURITY DEFINER implementations live in the unexposed private schema.

alter function public.employee_directory() set schema private;
alter function private.employee_directory() rename to employee_directory_impl;

alter function public.create_team(text, text, uuid, uuid[]) set schema private;
alter function private.create_team(text, text, uuid, uuid[]) rename to create_team_impl;

alter function public.manage_team_members(uuid, uuid[], uuid) set schema private;
alter function private.manage_team_members(uuid, uuid[], uuid) rename to manage_team_members_impl;

create or replace function public.employee_directory()
returns table(id uuid, employee_id text, display_name text, role public.app_role, is_active boolean)
language sql
stable
security invoker
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
  select * from private.employee_directory_impl()
$$;

create or replace function public.create_team(
  p_name text,
  p_description text default '',
  p_leader_id uuid default null,
  p_member_ids uuid[] default '{}'
)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
  select private.create_team_impl(p_name, p_description, p_leader_id, p_member_ids)
$$;

create or replace function public.manage_team_members(
  p_team_id uuid,
  p_member_ids uuid[] default '{}',
  p_leader_id uuid default null
)
returns void
language sql
volatile
security invoker
set search_path = pg_catalog, public, auth, private, pg_temp
as $$
  select private.manage_team_members_impl(p_team_id, p_member_ids, p_leader_id)
$$;

revoke all on function private.employee_directory_impl() from public, anon, authenticated;
revoke all on function private.create_team_impl(text, text, uuid, uuid[]) from public, anon, authenticated;
revoke all on function private.manage_team_members_impl(uuid, uuid[], uuid) from public, anon, authenticated;
grant execute on function private.employee_directory_impl() to authenticated;
grant execute on function private.create_team_impl(text, text, uuid, uuid[]) to authenticated;
grant execute on function private.manage_team_members_impl(uuid, uuid[], uuid) to authenticated;

revoke all on function public.employee_directory() from public, anon;
revoke all on function public.create_team(text, text, uuid, uuid[]) from public, anon;
revoke all on function public.manage_team_members(uuid, uuid[], uuid) from public, anon;
grant execute on function public.employee_directory() to authenticated;
grant execute on function public.create_team(text, text, uuid, uuid[]) to authenticated;
grant execute on function public.manage_team_members(uuid, uuid[], uuid) to authenticated;
