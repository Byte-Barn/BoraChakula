-- The demo dataset matches the design canvas story
declare
  l_d  number := hl_demo.featured_demand_id;
  l_f  hl_fulfil_v%rowtype;
  l_n  number;
  l_s  varchar2(400);
begin
  hlt.ok(l_d is not null, 'featured demand exists');
  select * into l_f from hl_fulfil_v where demand_id = l_d;
  hlt.eq(l_f.target_kg, 2000, 'featured target 2,000 kg');
  hlt.eq(l_f.matched_kg, 1200, 'featured confirmed 1,200 kg');
  hlt.eq(l_f.pending_kg, 700, 'featured pending 700 kg');
  hlt.eq(l_f.unmatched_kg, 100, 'featured open 100 kg');
  hlt.eq(l_f.fill_pct, 95, 'featured 95% filled');
  hlt.eq(l_f.receiving_window, '06-10', 'featured receiving window');

  select count(*) into l_n from hl_match_v where demand_id = l_d and ui_status <> 'DECLINED';
  hlt.eq(l_n, 4, 'four farms on the featured demand');
  select listagg(farmer_name, ',') within group (order by farmer_name) into l_s
    from hl_match_v where demand_id = l_d and ui_status = 'MATCHED';
  hlt.eq(l_s, 'Peter Kariuki,Wanjiru Muthoni', 'Wanjiru and Peter confirmed');
  select count(*) into l_n from hl_match_v where demand_id = l_d and farmer_phone like '+254%' and ui_status = 'PENDING';
  hlt.eq(l_n, 0, 'pending farmers phones are masked');
  select count(*) into l_n from hl_match_v where demand_id = l_d and reason_dist_state = 'warn';
  hlt.eq(l_n, 1, 'only the farthest farm gets a distance warning');

  select reason_window into l_s from hl_near_miss_v where demand_id = l_d and farmer_name = 'Joseph Mugo';
  hlt.ok(l_s like 'Harvest starts % after delivery %', 'Joseph Mugo not matched: harvest window');

  select sum(kg) into l_n from hl_grade_allocation_v where crop_name = 'Roma tomatoes' and grade = 'B';
  hlt.eq(l_n, 640, 'Grade B tomatoes 640 kg');
  select sum(kg) into l_n from hl_grade_allocation_v where crop_name = 'Roma tomatoes' and grade = 'C';
  hlt.eq(l_n, 310, 'Grade C tomatoes 310 kg');

  select count(*) into l_n from hl_impact_metrics_v;
  hlt.eq(l_n, 9, 'nine impact metrics');
  select count(*) into l_n from user_objects where status = 'INVALID';
  hlt.eq(l_n, 0, 'no invalid objects');
end;
/
