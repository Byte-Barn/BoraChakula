# HarvestLink operations runbook

Tasks for the operations team (`OPS` role). Run SQL as an `OPS` login in APEX SQL Workshop, or as `HARVESTLINK`.

## Farmer account deletion

A farmer can delete their own account; operations can do it on their behalf (for example after a phone call),
once the request is confirmed with the farmer.

```sql
begin
  hl_farmer_api.delete_account(p_farmer_id => :farmer_id);
  commit;
end;
```

What it does is in `docs/backend-api.md` (Farmer data rights). In short:

- Their open harvests, offers, allocations, pickup stops and login go at once, and their open demand is re-matched
  to other farms. Confirmed agreements are ended and recorded in the ledger under the pseudonym `Erased farmer #n`.
- **Delivered orders stay.** Harvests with a delivered match are kept, closed to matching, under a pseudonymous
  stub of the farmer row (no name, phone, village, cooperative or consent; location blurred to about 11 km). Buyers'
  closed orders keep their delivered kilograms and the impact figures do not drop. The stub shows as
  `Erased farmer #n` wherever a delivered order is listed.
- **The agreement ledger keeps the real name and phone** in the rows written before the deletion, until those rows
  are purged (below). Tell the farmer: "Your account is deleted now. Records of agreements you already made are
  locked for at least 16 days for fraud protection, and are deleted at the next ledger purge after that."

`HL_ERASURES` logs each deletion with no personal data: the pseudonym, how many ledger rows name the farmer, and
`PURGE_AFTER`, the date their newest row can be purged.

## Ledger purge

### Decision

`HL_AGREEMENTS` is a blockchain table. Oracle allows no update and no targeted delete: the only way to remove rows
is `DBMS_BLOCKCHAIN_TABLE.DELETE_EXPIRED_ROWS`, which deletes **every** row written before a cutoff once it is past
the 16-day retention. A purge for one erased farmer therefore also deletes every other party's agreement rows of
the same age.

**We accept that**, because:

- The right to deletion (Kenya Data Protection Act, 2019) has to be honoured; the ledger is the only place the
  name survives.
- The ledger is tamper evidence for recent agreements, not the business record. Orders, delivered kilograms and
  prices live in `HL_DEMANDS` and `HL_MATCHES`, which a purge does not touch (and deletion no longer removes
  delivered matches).
- Only rows older than the newest row naming an erased farmer, and at least 16 days old, can go.

The alternative raised in review, purging only once every older row is past retention for all parties, gives no
extra protection: Oracle already refuses to delete any row younger than 16 days, and every row older than the
cutoff is past retention by then. The only way to keep other parties' rows is never to purge, which leaves erased
farmers' names in the ledger indefinitely, so we do not do that.

What a purge costs, so it can be planned:

- `Agreements recorded` on the impact page counts ledger rows, so it drops by the purged confirmations.
- `HL_MATCH_V.AGREEMENT_HASH` is empty for purged matches.
- Verification (`DBMS_BLOCKCHAIN_TABLE.VERIFY_ROWS`) covers the rows that remain.

### When

Once a month, on the first working day, if `HL_LEDGER_PURGE_V` shows anything due. Batching keeps the number of
purges, and the other rows they take, predictable. Do not purge in the 48 hours before a demo or judging.

### Steps

1. **See what is due.**

   ```sql
   select * from hl_ledger_purge_v;
   ```

   `CUTOFF` null means nothing is due (`NEXT_DUE` says when the next erasure becomes due). Otherwise note
   `ROWS_TO_DELETE`, `ERASED_ROWS` (rows naming erased farmers) and `OTHER_ROWS` (other parties' rows that go too).

2. **Verify the chain** before changing it, and stop if it fails:

   ```sql
   declare n number;
   begin
     dbms_blockchain_table.verify_rows(user, 'HL_AGREEMENTS', number_of_rows_verified => n);
     dbms_output.put_line(n || ' rows verified');
   end;
   ```

3. **Purge** (operations only; `-20605` for anyone else):

   ```sql
   declare n number;
   begin
     n := hl_farmer_api.purge_ledger;
     dbms_output.put_line(n || ' rows deleted');
     commit;
   end;
   ```

4. **Check the log.** Each purge is recorded in `HL_LEDGER_PURGES` (cutoff, rows deleted, how many named erased
   farmers and how many belonged to other parties, who ran it). Erasures whose rows are gone get `PURGED_AT`:

   ```sql
   select * from hl_ledger_purges order by purge_id desc;
   select erasure_id, pseudonym, purge_after, purged_at from hl_erasures order by erasure_id desc;
   ```

   An erasure still without `PURGED_AT` after a purge means some of its rows were too young; it is picked up by
   the next monthly purge.

5. **Verify the chain again** (step 2).

## Market interview prices

Crop prices behind the income uplift come from FAOSTAT where FAO publishes a Kenyan price, otherwise from team
estimates (French beans and kale). Market interview answers replace them, crop by crop.

1. **Type up the forms.** For each "Broker price vs market price" answer on an interview record form (Appendix A of
   `docs/HarvestLink_Hackathon_Plan.pdf`), add a row to a copy of `docs/market-interviews-template.csv`:
   - `crop_name` exactly as in `HL_CROPS` (for example `Roma tomatoes`, `Kale (sukuma wiki)`);
   - `interviewee_role`: `FARMER`, `TRADER`, `BROKER` or `OTHER`;
   - prices in **KES per kg**. Convert crates and bags in the sheet (a tomato crate is about 64 kg) and keep the
     answer as given in `quoted_as`. Leave a price empty if it was not asked;
   - no names or phone numbers (first names stay on the paper form).

2. **Load the rows** into `HL_PRICE_OBSERVATIONS`: APEX SQL Workshop → Utilities → Data Workshop → Load Data, into
   the existing table, or `insert` statements in SQL Commands.

3. **Compare** the medians with the prices in use, and look at the range for answers typed in the wrong unit:

   ```sql
   select crop_name, broker_observations, broker_median_kg, broker_min_kg, broker_max_kg,
          broker_price_in_use, broker_price_source,
          market_observations, market_median_kg, market_price_in_use
     from hl_price_summary_v
    order by crop_name;
   ```

4. **Apply** the medians for crops with enough answers (default 3; operations only):

   ```sql
   declare n pls_integer;
   begin
     n := hl_calibration.apply_interview_prices(p_min_observations => 3);
     dbms_output.put_line(n || ' prices changed');
     commit;
   end;
   ```

   Each changed price gets basis `INTERVIEW` and a source such as "Market interviews, Murang'a town market,
   15 Oct 2026: median of 6". The impact page's income uplift then lists the prices it used with their sources,
   and shows `sourced` while none of the crops in current orders rely on an estimate.

5. **Keep the seed in step**: copy the applied prices and sources into `db/04_seed.sql` (the `hl_crops` inserts
   and the `update hl_crops` basis block) in a pull request, so a rebuild keeps them.
