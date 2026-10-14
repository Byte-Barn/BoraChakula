-- Demand and harvest API rules and flows
declare
  l_buyer number; l_crop number; l_farmer number; l_d number; l_m number; l_h number; l_n number;
  l_f hl_fulfil_v%rowtype;
begin
  select buyer_id into l_buyer from hl_buyers where buyer_name = 'Gikomba Fresh Wholesalers';
  select crop_id into l_crop from hl_crops where crop_name = 'Roma tomatoes';
  select farmer_id into l_farmer from hl_farmers where full_name = 'Joseph Mugo';

  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''A'', 0, 70, sysdate + 10); end;', -20201, 'zero quantity refused');
  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''A'', 60000, 70, sysdate + 10); end;', -20201, 'over 50 t refused');
  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''A'', 500, 70, sysdate + 2); end;', -20202, 'short lead time refused');
  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''D'', 500, 70, sysdate + 10); end;', -20203, 'bad grade refused');
  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''A'', 500, 0, sysdate + 10); end;', -20204, 'zero price refused');
  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''A'', 500, 70, sysdate + 10, p_delivery_lat => -1); end;', -20205, 'half a location refused');
  hlt.raises('declare n number; begin n := hl_demand_api.create_demand(1, 1, ''A'', 500, 70, sysdate + 10, p_receiving_window => ''09-11''); end;', -20208, 'bad receiving window refused');
  hlt.raises('declare n number; begin n := hl_harvest_api.register(1, 1, ''A'', 300, sysdate + 5, sysdate + 3); end;', -20212, 'reversed harvest window refused');
  hlt.raises('declare n number; begin n := hl_harvest_api.register(1, 1, ''A'', 300, sysdate - 5, sysdate + 3); end;', -20213, 'past harvest start refused');

  -- Create, confirm, decline, cancel
  l_d := hl_demand_api.create_demand(l_buyer, l_crop, 'B', 500, 55, sysdate + 9);
  select * into l_f from hl_fulfil_v where demand_id = l_d;
  hlt.ok(l_f.pending_kg > 0, 'new demand is matched immediately');
  select min(match_id) keep (dense_rank first order by rank_no) into l_m from hl_match_v where demand_id = l_d and ui_status = 'PENDING';
  hl_match_pkg.confirm(l_m);
  select count(*) into l_n from hl_agreements where match_id = l_m and event = 'ACCEPTED';
  hlt.eq(l_n, 1, 'confirm writes an ACCEPTED ledger row');
  hlt.raises('hl_match_pkg.confirm(' || l_m || ');', -20111, 'confirming twice refused');
  select harvest_id into l_h from hl_matches where match_id = l_m;
  hlt.raises('hl_harvest_api.update_estimate(' || l_h || ', 100, sysdate + 1, sysdate + 3);', -20215, 'promised harvest cannot change');
  hl_match_pkg.decline(l_m);
  select ui_status into l_f.status from hl_match_v where match_id = l_m;
  hlt.eq(l_f.status, 'DECLINED', 'decline marks the match declined');
  select count(*) into l_n from hl_agreements where match_id = l_m and event = 'REJECTED';
  hlt.eq(l_n, 1, 'declining a confirmed match writes REJECTED');
  hl_demand_api.cancel(l_d);
  select status, matched_kg + pending_kg into l_f.status, l_n from hl_fulfil_v where demand_id = l_d;
  hlt.eq(l_f.status || ' ' || l_n, 'CANCELLED 0', 'cancel releases all supply');

  -- Drafts
  l_d := hl_demand_api.save_draft(p_buyer_id => l_buyer, p_crop_id => l_crop, p_grade => 'B', p_quantity_kg => 200,
                                  p_price_per_kg => 50, p_need_by_date => sysdate + 3, p_receiving_window => '10-14');
  hl_match_pkg.rerun_open;
  select count(*) into l_n from hl_matches where demand_id = l_d;
  hlt.eq(l_n, 0, 'drafts are not matched');
  hlt.raises('hl_demand_api.publish(' || l_d || ');', -20202, 'publish applies the lead-time rule');
  l_d := hl_demand_api.save_draft(p_demand_id => l_d, p_buyer_id => l_buyer, p_crop_id => l_crop, p_grade => 'B',
                                  p_quantity_kg => 200, p_price_per_kg => 50, p_need_by_date => sysdate + 12);
  hl_demand_api.publish(l_d);
  select count(*) into l_n from hl_matches where demand_id = l_d;
  hlt.ok(l_n > 0, 'published draft is matched');

  -- Harvest registration
  l_h := hl_harvest_api.register(l_farmer, l_crop, 'A', 300, sysdate + 5, sysdate + 8);
  hlt.ok(l_h is not null, 'harvest registered');
  rollback;
end;
/
