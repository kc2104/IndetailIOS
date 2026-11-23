-- Restrict the Data API to authenticated users and limit client-side table privileges.
-- RLS policies continue to decide which rows each authenticated user may access.
revoke all on schema public from anon;
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;

grant usage on schema public to authenticated;
revoke all on all tables in schema public from authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
revoke all on all sequences in schema public from authenticated;
grant usage, select on all sequences in schema public to authenticated;

-- Punches and audit rows are written only by the validated RPC and database triggers.
revoke insert, update, delete on public.attendance_sessions from authenticated;
revoke insert, update, delete on public.attendance_events from authenticated;
revoke insert, update, delete on public.audit_logs from authenticated;

-- Keep future tables and sequences private until a migration explicitly grants access.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
