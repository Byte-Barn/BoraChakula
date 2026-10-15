-- Who may act on a match and see a confirmed farmer's phone number
declare
  l_d       number := hl_demo.featured_demand_id;   -- Kijani Fresh Grocers' order
  l_pending number;
  l_own     number;
  l_n       number;
  l_harvest number;
begin
  select min(match_id) into l_pending from hl_matches where demand_id = l_d and status = 'PROPOSED';
  select min(m.match_id) into l_own
    from hl_matches m join hl_harvests h on h.harvest_id = m.harvest_id
    join hl_farmers f on f.farmer_id = h.farmer_id
   where f.full_name = 'Wanjiru Muthoni';

  -- Scripts outside APEX keep full access
  select count(*) into l_n from hl_match_v where demand_id = l_d and ui_status = 'MATCHED' and farmer_phone like '+254%';
  hlt.ok(l_n >= 1, 'scripts see confirmed farmers'' phone numbers');

  -- Another buyer
  hl_auth.register_user('HLT_OTHER_BUYER', 'BUYER', 'Gikomba Fresh Wholesalers');
  hl_auth.set_user('HLT_OTHER_BUYER');
  select count(*) into l_n from hl_match_v where demand_id = l_d and farmer_phone like '+254%';
  hlt.eq(l_n, 0, 'another buyer sees no farmer phone numbers on the order');
  hlt.eq(hl_match_pkg.can_act(l_d, null), 'N', 'another buyer cannot act on the order');
  hlt.raises('hl_match_pkg.confirm(' || l_pending || ');', -20113, 'another buyer cannot confirm a farmer');
  hlt.raises('hl_match_pkg.decline(' || l_pending || ');', -20113, 'another buyer cannot decline a farmer');
  hlt.raises('hl_match_pkg.run(' || l_d || ');', -20113, 'another buyer cannot re-run matching');
  hlt.raises('hl_match_pkg.rerun_open;', -20113, 'a buyer cannot re-match every demand');

  -- The buyer who owns the order
  hl_auth.set_user('BUYER_DEMO');
  select count(*) into l_n from hl_match_v where demand_id = l_d and ui_status = 'MATCHED' and farmer_phone like '+254%';
  hlt.ok(l_n >= 1, 'the owning buyer sees confirmed farmers'' phone numbers');
  hlt.eq(hl_match_pkg.can_act(l_d, null), 'Y', 'the owning buyer can act on the order');

  -- A farmer: own offers only
  hl_auth.set_user('FARMER_DEMO');
  select harvest_id into l_harvest from hl_matches where match_id = l_own;
  hlt.eq(hl_match_pkg.can_act(null, l_harvest), 'Y', 'a farmer can act on her own offer');
  hlt.raises('hl_match_pkg.confirm(' || l_pending || ');', -20113, 'a farmer cannot confirm another farmer''s offer');

  -- Operations
  hl_auth.set_user('OPS_DEMO');
  hlt.eq(hl_match_pkg.can_act(l_d, null), 'Y', 'operations can act on any order');

  hl_auth.set_user(null);
  rollback;
end;
/
