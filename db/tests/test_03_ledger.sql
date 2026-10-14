-- The agreement ledger is append-only and its hash chain verifies
declare
  l_n number;
begin
  select count(*) into l_n from hl_agreements;
  hlt.ok(l_n >= 9, 'demo confirmations are in the ledger');
  hlt.raises('update hl_agreements set quantity_kg = 1;', -5715, 'ledger rows cannot be updated');
  hlt.raises('delete from hl_agreements;', -5715, 'ledger rows cannot be deleted');
  dbms_blockchain_table.verify_rows(user, 'HL_AGREEMENTS', number_of_rows_verified => l_n);
  hlt.ok(l_n >= 9, 'hash chain verifies (' || l_n || ' rows)');
end;
/
