-- Balance changes are only written through the Admin RPC. Keep direct table
-- access explicitly denied for authenticated app users and index the audit FK.
create policy paid_leave_balance_adjustments_deny_authenticated
  on public.paid_leave_balance_adjustments
  for all to authenticated
  using (false)
  with check (false);

create index if not exists paid_leave_balance_adjustments_created_by_idx
  on public.paid_leave_balance_adjustments(created_by);
