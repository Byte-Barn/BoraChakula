-- Farmer data rights: consent, export, access control, account deletion
declare
  l_peter  number; l_wanjiru number; l_grace number; l_n number; l_s varchar2(4000);
  l_closed_kg number; l_delivered_kg number; l_kg number;
  l_f      hl_farmers%rowtype;
  l_json   clob;
  l_e      hl_erasures%rowtype;
  l_d      number := hl_demo.featured_demand_id;
begin
  select farmer_id into l_peter   from hl_farmers where full_name = 'Peter Kariuki';
  select farmer_id into l_wanjiru from hl_farmers where full_name = 'Wanjiru Muthoni';
  select farmer_id into l_grace   from hl_farmers where full_name = 'Grace Wambui';

  -- Consent
  select count(*) into l_n from hl_farmers where consent_given = 'Y' and consent_version = '2026-10-v1' and consent_at is not null;
  hlt.eq(l_n, 10, 'demo farmers carry consent version and time');
  hlt.raises('hl_farmer_api.record_consent(' || l_grace || ', ''v99'');', -20602, 'unknown consent notice refused');
  hlt.raises('hl_farmer_api.record_consent(-1);', -20601, 'unknown farmer refused');

  -- Export
  l_json := hl_farmer_api.export_data(l_wanjiru);
  hlt.ok(l_json is json, 'export is valid JSON');
  select count(*) into l_n from json_table(l_json, '$.harvests[*]' columns (id number path '$.harvest_id'));
  hlt.eq(l_n, 4, 'export lists her 4 harvests');
  select count(*) into l_n from json_table(l_json, '$.agreement_ledger[*]' columns (e varchar2(20) path '$.event'));
  hlt.ok(l_n >= 3, 'export includes her ledger rows');
  hlt.ok(json_value(l_json, '$.consent.notice_text') like 'HarvestLink keeps%', 'export includes the consent notice');

  -- Access control
  hl_auth.set_user('FARMER_DEMO');
  hlt.raises('declare c clob; begin c := hl_farmer_api.export_data(' || l_peter || '); end;', -20603, 'farmer cannot export another farmer');
  select count(*) into l_n from hl_my_data_v where data_json is json;
  hlt.eq(l_n, 1, 'farmer sees own data in HL_MY_DATA_V');
  hl_auth.set_user('BUYER_DEMO');
  hlt.raises('hl_farmer_api.delete_account(' || l_peter || ');', -20603, 'buyer cannot delete a farmer');
  hlt.raises('declare n number; begin n := hl_farmer_api.purge_ledger; end;', -20605, 'buyer cannot purge the ledger');
  hl_auth.set_user(null);

  -- Delete Peter: confirmed on the featured demand, with delivered history
  select nvl(sum(matched_kg), 0) into l_closed_kg from hl_fulfil_v where status = 'CLOSED';
  select nvl(sum(allocated_kg), 0) into l_delivered_kg from hl_matches where status = 'DELIVERED';
  hlt.ok(l_closed_kg > 0, 'demo has a closed order with delivered kg');
  hl_farmer_api.delete_account(l_peter);

  -- Delivered history stays, so buyer records and impact hold
  select nvl(sum(matched_kg), 0) into l_kg from hl_fulfil_v where status = 'CLOSED';
  hlt.eq(l_kg, l_closed_kg, 'closed orders keep their delivered kg');
  select nvl(sum(allocated_kg), 0) into l_kg from hl_matches where status = 'DELIVERED';
  hlt.eq(l_kg, l_delivered_kg, 'delivered kg unchanged overall');
  select * into l_f from hl_farmers where farmer_id = l_peter;
  hlt.ok(l_f.erased_at is not null and l_f.full_name like 'Erased farmer #%' and l_f.phone like 'ERASED-%'
         and l_f.location_name is null and l_f.cooperative is null and l_f.consent_given = 'N'
         and l_f.latitude = round(l_f.latitude, 1),
         'farmer row kept only as a pseudonymous stub for the delivered order');
  select count(*) into l_n from hl_harvests where farmer_id = l_peter and status <> 'HARVESTED';
  hlt.eq(l_n, 0, 'open harvests deleted; kept harvests closed to matching');
  select count(*) into l_n
    from hl_matches m join hl_harvests h on h.harvest_id = m.harvest_id
   where h.farmer_id = l_peter and m.status <> 'DELIVERED';
  hlt.eq(l_n, 0, 'only delivered matches remain, and re-matching adds none');
  select count(*) into l_n from hl_match_v where farmer_name like '%Peter%' or farmer_phone like '%000102';
  hlt.eq(l_n, 0, 'gone from matches');
  select count(*) into l_n from hl_match_v where farmer_id = l_peter and match_status = 'DELIVERED' and farmer_name like 'Erased farmer #%';
  hlt.eq(l_n, 1, 'delivered match shows the pseudonym');
  hlt.raises('hl_farmer_api.delete_account(' || l_peter || ');', -20606, 'a deleted account cannot be deleted again');
  hlt.raises('declare c clob; begin c := hl_farmer_api.export_data(' || l_peter || '); end;', -20606, 'a deleted account has no export');
  select * into l_e from hl_erasures where farmer_id = l_peter;
  hlt.ok(l_e.purge_after > systimestamp + interval '15' day, 'erasure logged with a purge date 16 days after the last ledger row');
  select count(*) into l_n from hl_agreements where event = 'REJECTED' and farmer_name = l_e.pseudonym and farmer_phone like 'ERASED-%';
  hlt.eq(l_n, 1, 'confirmed agreement ended under a pseudonym');
  select count(*) into l_n from hl_agreements where farmer_name = 'Peter Kariuki' and recorded_at > l_e.requested_at;
  hlt.eq(l_n, 0, 'no new ledger row carries the real name');
  select count(*) into l_n from hl_route_stops where stop_name = 'Peter Kariuki' or place = 'Mwea';
  hlt.eq(l_n, 0, 'removed from pickup stops');
  select count(*) into l_n from hl_routes where instr(route_sequence, 'Peter Kariuki') > 0;
  hlt.eq(l_n, 0, 'removed from route stop lists');
  select status into l_s from hl_demands where demand_id = l_d;
  hlt.ok(l_s in ('OPEN', 'PARTIAL', 'FILLED'), 'featured demand still active after re-matching');
  hlt.eq(hl_farmer_api.purge_ledger, 0, 'nothing purgeable before 16 days');

  -- Grace has no delivered history: her row goes entirely
  hl_farmer_api.delete_account(l_grace);
  select count(*) into l_n from hl_farmers where farmer_id = l_grace;
  hlt.eq(l_n, 0, 'farmer without delivered history: row deleted');
  select count(*) into l_n from user_objects where status = 'INVALID';
  hlt.eq(l_n, 0, 'no invalid objects after deletion');

  -- Deleting the demo farmer removes her login; reset restores it
  hl_farmer_api.delete_account(l_wanjiru);
  hlt.eq(hl_auth.role('FARMER_DEMO'), null, 'deleted farmer loses her login mapping');
  hl_demo.reset;
  hlt.eq(hl_auth.role('FARMER_DEMO'), 'FARMER', 'hl_demo.reset restores FARMER_DEMO');
  hlt.ok(hl_auth.farmer_id('FARMER_DEMO') is not null, 'FARMER_DEMO resolves to the reseeded farmer');
end;
/
