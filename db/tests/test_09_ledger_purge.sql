-- Ledger purge after account deletion. Rows cannot be deleted until 16 days
-- after insert, so this checks the preview, the audit log and that the purge
-- removes nothing still in retention. Runs after test_07 (erasures pending)
-- and test_08_ai, which leaves farmers alone.
declare
  l_v       hl_ledger_purge_v%rowtype;
  l_before  number;
  l_n       number;
  l_log     hl_ledger_purges%rowtype;
begin
  select count(*) into l_before from hl_agreements;

  -- Nothing due yet
  select * into l_v from hl_ledger_purge_v;
  hlt.ok(l_v.cutoff is null and l_v.due_erasures = 0 and l_v.rows_to_delete = 0, 'nothing due within 16 days');
  hlt.ok(l_v.next_due > systimestamp + interval '15' day, 'next purge date shown');

  -- Pretend the retention window has passed for the pending erasures
  update hl_erasures set purge_after = systimestamp - interval '1' minute where purged_at is null;
  select * into l_v from hl_ledger_purge_v;
  hlt.ok(l_v.cutoff is not null and l_v.due_erasures >= 1, 'due erasures give a cutoff');
  hlt.ok(l_v.erased_rows >= 1, 'preview counts rows naming erased farmers');
  hlt.ok(l_v.other_rows >= 1, 'preview counts other parties'' rows that would go too');
  hlt.eq(l_v.rows_to_delete, l_v.erased_rows + l_v.other_rows, 'preview adds up');

  -- Oracle still refuses rows younger than 16 days: nothing is deleted
  hlt.eq(hl_farmer_api.purge_ledger, 0, 'purge deletes nothing still in retention');
  select count(*) into l_n from hl_agreements;
  hlt.eq(l_n, l_before, 'ledger unchanged');
  select * into l_log from hl_ledger_purges order by purge_id desc fetch first 1 row only;
  hlt.ok(l_log.rows_deleted = 0 and l_log.other_rows = 0 and l_log.cutoff = l_v.cutoff, 'purge logged with its cutoff and counts');
  select count(*) into l_n from hl_erasures where purged_at is null;
  hlt.ok(l_n >= 1, 'erasures stay pending while their rows remain');
  rollback;
end;
/
