-- HarvestLink: tamper-evident agreement ledger.
--
-- Every time a farmer's match is confirmed, rejected after confirmation, or
-- delivered, one row is appended to HL_AGREEMENTS, an Oracle blockchain
-- table: rows cannot be updated, cannot be deleted for 16 days, and each row
-- carries a SHA2-512 hash chained to the row before it, so any tampering
-- shows up when the chain is verified.
--
-- The row copies the terms (farmer, buyer, crop, grade, kg, price) rather than
-- pointing at them, so the record stays meaningful if a demand, harvest or
-- match is later edited or deleted.

create blockchain table hl_agreements (
  match_id       number         not null,
  event          varchar2(20)   not null,   -- ACCEPTED, REJECTED, DELIVERED
  demand_id      number         not null,
  harvest_id     number         not null,
  farmer_name    varchar2(100)  not null,
  farmer_phone   varchar2(20),
  buyer_name     varchar2(150)  not null,
  crop_name      varchar2(60)   not null,
  grade          varchar2(1)    not null,
  quantity_kg    number(10,2)   not null,
  price_per_kg   number(10,2)   not null,
  value_kes      number(14,2)   not null,
  need_by_date   date           not null,
  recorded_by    varchar2(255)  not null,
  recorded_at    timestamp      not null
)
no drop until 0 days idle                 -- the demo reset may drop and rebuild it
no delete until 16 days after insert      -- the shortest retention Oracle allows
hashing using "SHA2_512" version "v2";

create index hl_agreements_match_ix on hl_agreements (match_id);

-- Append a ledger row when a match is confirmed, or a confirmed match is
-- rejected or delivered
create or replace trigger hl_matches_agreement
after update of status on hl_matches
for each row
when (new.status in ('ACCEPTED', 'DELIVERED')
      or (new.status = 'REJECTED' and old.status in ('ACCEPTED', 'DELIVERED')))
begin
  insert into hl_agreements (
    match_id, event, demand_id, harvest_id, farmer_name, farmer_phone,
    buyer_name, crop_name, grade, quantity_kg, price_per_kg, value_kes,
    need_by_date, recorded_by, recorded_at)
  select :new.match_id, :new.status, d.demand_id, h.harvest_id, f.full_name, f.phone,
         b.buyer_name, c.crop_name, h.grade, :new.allocated_kg, d.price_per_kg,
         round(:new.allocated_kg * d.price_per_kg, 2), d.need_by_date,
         coalesce(sys_context('APEX$SESSION', 'APP_USER'), sys_context('USERENV', 'SESSION_USER')),
         systimestamp
    from hl_demands d
    join hl_buyers b on b.buyer_id = d.buyer_id
    join hl_harvests h on h.harvest_id = :new.harvest_id
    join hl_farmers f on f.farmer_id = h.farmer_id
    join hl_crops c on c.crop_id = h.crop_id
   where d.demand_id = :new.demand_id;
end;
/

-- Ledger with the hidden blockchain columns exposed for display: position in
-- the chain and the row hash (first 16 hex digits are enough to show on screen)
create or replace view hl_agreements_v as
select a.match_id,
       a.event,
       a.demand_id,
       a.harvest_id,
       a.farmer_name,
       a.farmer_phone,
       a.buyer_name,
       a.crop_name,
       a.grade,
       a.quantity_kg,
       a.price_per_kg,
       a.value_kes,
       a.need_by_date,
       a.recorded_by,
       a.recorded_at,
       a.orabctab_chain_id$                 as chain_id,
       a.orabctab_seq_num$                  as chain_seq,
       rawtohex(a.orabctab_hash$)           as row_hash,
       substr(rawtohex(a.orabctab_hash$), 1, 16) as row_hash_short
  from hl_agreements a;

-- Demo: the two highest-ranked farmers on the first demand have confirmed
begin
  for r in (select match_id
              from hl_matches
             where demand_id = (select min(demand_id) from hl_matches)
               and status = 'PROPOSED'
             order by score_total desc
             fetch first 2 rows only)
  loop
    hl_match_pkg.accept_match(r.match_id);
  end loop;
  commit;
end;
/
