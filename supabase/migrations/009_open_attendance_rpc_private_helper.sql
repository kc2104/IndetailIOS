-- Keep the PostgREST-facing endpoint invoker-secured while using a narrowly
-- scoped private helper to read only the caller's own active shift site.
create or replace function private.my_open_attendance_site_impl()
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

revoke all on function private.my_open_attendance_site_impl() from public, anon;
grant execute on function private.my_open_attendance_site_impl() to authenticated;

create or replace function public.my_open_attendance_site()
returns jsonb
language sql
security invoker
set search_path to 'pg_catalog', 'public', 'private', 'auth', 'pg_temp'
as $function$
  select private.my_open_attendance_site_impl()
$function$;

revoke all on function public.my_open_attendance_site() from public, anon;
grant execute on function public.my_open_attendance_site() to authenticated;
