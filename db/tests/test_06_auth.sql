-- Roles and "my" views
declare
  l_n number;
begin
  hlt.eq(hl_auth.role('BUYER_DEMO'), 'BUYER', 'BUYER_DEMO is a buyer');
  hlt.eq(hl_auth.role('FARMER_DEMO'), 'FARMER', 'FARMER_DEMO is a farmer');
  hlt.eq(hl_auth.role('OPS_DEMO'), 'OPS', 'OPS_DEMO is operations');
  hlt.eq(hl_auth.role('NOBODY'), null, 'unknown login has no role');
  hl_auth.set_user('BUYER_DEMO');
  hlt.ok(hl_auth.is_buyer and not hl_auth.is_ops, 'buyer flags');
  select count(*) into l_n from hl_my_demands_v;
  hlt.eq(l_n, 5, 'buyer sees Kijani''s 5 demands');
  hl_auth.set_user('FARMER_DEMO');
  select count(*) into l_n from hl_my_offers_v;
  hlt.eq(l_n, 2, 'farmer sees her 2 offers');
  hl_demo.reset;
  select count(*) into l_n from hl_my_harvests_v;
  hlt.eq(l_n, 4, 'farmer login survives hl_demo.reset');
  hl_auth.set_user(null);
  hlt.raises('hl_auth.register_user(''X'', ''ADMIN'');', -20501, 'bad role refused');
  hlt.raises('hl_auth.register_user(''X'', ''BUYER'', ''Nobody Ltd'');', -20502, 'unknown party refused');
end;
/
