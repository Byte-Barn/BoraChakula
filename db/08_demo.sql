-- =============================================================================
-- HL_DEMO: the demo dataset from the design canvas, and a one-call reset.
--
-- Story: Kijani Fresh Grocers (Westlands, Nairobi) needs 2 t of Grade A Roma
-- tomatoes in 14 days. No single farm can supply it; four farms in Kirinyaga
-- cover 1,900 kg (95%). Wanjiru and Peter have confirmed, Grace and Esther
-- are pending, and Joseph Mugo is not matched because his harvest starts after
-- the delivery date. The same four farms hold 640 kg of Grade B and 310 kg of
-- Grade C for grade routing. Kijani's other orders (onions, peppers, carrots
-- in transit, an earlier delivered tomato order) fill the buyer dashboard.
--
-- People and businesses are fictional. Coordinates are approximate town
-- centres. Dates are relative to today so the demo always looks current.
--
-- hl_demo.reset clears demand, supply, matches and routes and loads the
-- story again. The agreement ledger is a blockchain table and is never
-- cleared: earlier rehearsal confirmations stay in it, as they should.
-- =============================================================================

create or replace package hl_demo as

  -- Loads the dataset into empty demo tables and runs matching once
  procedure seed;

  -- Deletes all farmers, buyers, harvests, demands, matches and routes,
  -- then seeds again. Commits.
  procedure reset;

  -- The Kijani 2 t tomato demand featured on the landing and matching pages
  function featured_demand_id return number;

end hl_demo;
/

create or replace package body hl_demo as

  c_buyer_name constant varchar2(150) := 'Kijani Fresh Grocers';

  function crop (p_name in varchar2) return number is
    l_id hl_crops.crop_id%type;
  begin
    select crop_id into l_id from hl_crops where crop_name = p_name;
    return l_id;
  end crop;

  function add_farmer (
    p_name in varchar2, p_phone in varchar2, p_place in varchar2,
    p_lat in number, p_lon in number, p_coop in varchar2, p_smartphone in varchar2
  ) return number is
    l_id hl_farmers.farmer_id%type;
  begin
    insert into hl_farmers (full_name, phone, county, location_name, latitude, longitude,
                            cooperative, has_smartphone, consent_given)
    values (p_name, p_phone, 'Kirinyaga', p_place, p_lat, p_lon, p_coop, p_smartphone, 'Y')
    returning farmer_id into l_id;
    return l_id;
  end add_farmer;

  function add_buyer (
    p_name in varchar2, p_type in varchar2, p_county in varchar2, p_place in varchar2,
    p_lat in number, p_lon in number, p_grades in varchar2, p_kra in varchar2, p_verified in varchar2
  ) return number is
    l_id hl_buyers.buyer_id%type;
  begin
    insert into hl_buyers (buyer_name, buyer_type, county, location_name, latitude, longitude,
                           accepted_grades, kra_pin, is_verified)
    values (p_name, p_type, p_county, p_place, p_lat, p_lon, p_grades, p_kra, p_verified)
    returning buyer_id into l_id;
    return l_id;
  end add_buyer;

  -- Harvest window as days from today
  function add_harvest (
    p_farmer in number, p_crop in varchar2, p_grade in varchar2, p_kg in number,
    p_from in pls_integer, p_to in pls_integer, p_status in varchar2 default 'OPEN'
  ) return number is
    l_id   hl_harvests.harvest_id%type;
    l_crop hl_crops.crop_id%type := crop(p_crop);
  begin
    insert into hl_harvests (farmer_id, crop_id, grade, expected_qty_kg,
                             harvest_from, harvest_to, status)
    values (p_farmer, l_crop, p_grade, p_kg,
            trunc(sysdate) + p_from, trunc(sysdate) + p_to, p_status)
    returning harvest_id into l_id;
    return l_id;
  end add_harvest;

  function add_demand (
    p_buyer in number, p_crop in varchar2, p_grade in varchar2, p_kg in number,
    p_price in number, p_need_by in pls_integer, p_notes in varchar2,
    p_status in varchar2 default 'OPEN'
  ) return number is
    l_id   hl_demands.demand_id%type;
    l_crop hl_crops.crop_id%type := crop(p_crop);
  begin
    insert into hl_demands (buyer_id, crop_id, grade_required, quantity_kg, price_per_kg,
                            need_by_date, notes, status)
    values (p_buyer, l_crop, p_grade, p_kg, p_price,
            trunc(sysdate) + p_need_by, p_notes, p_status)
    returning demand_id into l_id;
    return l_id;
  end add_demand;

  -- The farmer's yes, as a field agent would record it
  procedure confirm (p_demand in number, p_farmer in number) is
  begin
    for m in (select m.match_id
                from hl_matches m
                join hl_harvests h on h.harvest_id = m.harvest_id
               where m.demand_id = p_demand
                 and h.farmer_id = p_farmer
                 and m.status = 'PROPOSED') loop
      hl_match_pkg.confirm(m.match_id);
    end loop;
  end confirm;

  -- A past order: matched, confirmed and delivered (goes through the ledger)
  procedure delivered (p_demand in number, p_harvest in number, p_kg in number, p_buyer in number) is
    l_match hl_matches.match_id%type;
    l_km    number;
  begin
    select hl_match_pkg.distance_km(f.latitude, f.longitude, b.latitude, b.longitude)
      into l_km
      from hl_harvests h
      join hl_farmers f on f.farmer_id = h.farmer_id
     cross join hl_buyers b
     where h.harvest_id = p_harvest and b.buyer_id = p_buyer;

    insert into hl_matches (demand_id, harvest_id, allocated_kg, distance_km, score_total,
                            score_quantity, score_grade, score_timing, score_distance, match_reason)
    values (p_demand, p_harvest, p_kg, l_km, 0.8, 0.6, 1, 0.9, 0.7, 'Earlier order, delivered')
    returning match_id into l_match;
    update hl_matches set status = 'ACCEPTED'  where match_id = l_match;
    update hl_matches set status = 'DELIVERED' where match_id = l_match;
  end delivered;

  procedure seed is
    l_kijani number; l_d_tomato number; l_d_onion number; l_d_pepper number;
    l_d_carrot number; l_d_history number;
    l_wanjiru number; l_peter number; l_grace number; l_esther number; l_joseph number;
    l_samuel number; l_lucy number; l_john number; l_mary number; l_daniel number;
    l_h number; l_count number;
  begin
    select count(*) into l_count from hl_farmers;
    if l_count > 0 then
      raise_application_error(-20301, 'Demo tables are not empty; use hl_demo.reset');
    end if;

    hl_match_pkg.g_auto_match := false;

    -- Buyers: the canvas buyer, plus outlets for Grade B and C produce
    l_kijani := add_buyer(c_buyer_name, 'RETAILER', 'Nairobi', 'Westlands',
                          -1.2676, 36.8108, 'A,B', 'P000000101K', 'Y');
    l_h := add_buyer('Gikomba Fresh Wholesalers', 'WHOLESALE_MARKET', 'Nairobi', 'Gikomba',
                     -1.2833, 36.8417, 'A,B,C', 'P000000102L', 'Y');
    l_h := add_buyer('Thika Tomato Processors', 'PROCESSOR', 'Kiambu', 'Thika',
                     -1.0333, 37.0693, 'B,C', 'P000000103M', 'Y');
    l_h := add_buyer('Murang''a Schools Feeding Programme', 'SCHOOL', 'Murang''a', 'Murang''a Town',
                     -0.7210, 37.1526, 'A,B', null, 'Y');
    l_h := add_buyer('Mto Hotels Thika', 'HOTEL', 'Kiambu', 'Thika',
                     -1.0400, 37.0800, 'A,B', 'P000000105P', 'N');

    -- Farmers in Kirinyaga
    l_wanjiru := add_farmer('Wanjiru Muthoni', '+254711000101', 'Kagio',     -0.6267, 37.2717, 'Kagio Horticulture Group', 'Y');
    l_peter   := add_farmer('Peter Kariuki',   '+254711000102', 'Mwea',      -0.6811, 37.3611, 'Mwea Growers Cooperative', 'Y');
    l_grace   := add_farmer('Grace Wambui',    '+254711000103', 'Kutus',     -0.5667, 37.3167, null,                        'N');
    l_esther  := add_farmer('Esther Wangui',   '+254711000104', 'Baricho',   -0.5833, 37.2333, 'Kagio Horticulture Group', 'N');
    l_joseph  := add_farmer('Joseph Mugo',     '+254711000105', 'Kerugoya',  -0.4986, 37.2803, null,                        'Y');
    l_samuel  := add_farmer('Samuel Njeru',    '+254711000106', 'Kianyaga',  -0.4917, 37.3500, 'Kianyaga Farmers Group',   'Y');
    l_lucy    := add_farmer('Lucy Wairimu',    '+254711000107', 'Sagana',    -0.6667, 37.2083, null,                        'N');
    l_john    := add_farmer('John Kinyua',     '+254711000108', 'Kerugoya',  -0.5050, 37.2850, 'Kianyaga Farmers Group',   'Y');
    l_mary    := add_farmer('Mary Nyambura',   '+254711000109', 'Kangaita',  -0.4667, 37.2667, null,                        'N');
    l_daniel  := add_farmer('Daniel Gitonga',  '+254711000110', 'Kiamutugu', -0.5500, 37.3833, 'Mwea Growers Cooperative', 'Y');

    -- Featured order: 2 t of Grade A Roma tomatoes in 14 days
    l_d_tomato := add_demand(l_kijani, 'Roma tomatoes', 'A', 2000, 75, 14,
                             'Plastic crates only, no sacks. Gate 2, ask for Mary.');
    l_h := add_harvest(l_wanjiru, 'Roma tomatoes', 'A', 650,  8, 12);
    l_h := add_harvest(l_peter,   'Roma tomatoes', 'A', 550,  9, 13);
    l_h := add_harvest(l_grace,   'Roma tomatoes', 'A', 450, 10, 13);
    l_h := add_harvest(l_esther,  'Roma tomatoes', 'A', 250, 11, 13);
    l_h := add_harvest(l_joseph,  'Roma tomatoes', 'A', 380, 16, 20);  -- starts after delivery
    -- Lower grades from the same farms, for grade routing (640 kg B, 310 kg C)
    l_h := add_harvest(l_wanjiru, 'Roma tomatoes', 'B', 220,  8, 12);
    l_h := add_harvest(l_peter,   'Roma tomatoes', 'B', 180,  9, 13);
    l_h := add_harvest(l_grace,   'Roma tomatoes', 'B', 140, 10, 13);
    l_h := add_harvest(l_esther,  'Roma tomatoes', 'B', 100, 11, 13);
    l_h := add_harvest(l_wanjiru, 'Roma tomatoes', 'C', 100,  8, 12);
    l_h := add_harvest(l_peter,   'Roma tomatoes', 'C',  90,  9, 13);
    l_h := add_harvest(l_grace,   'Roma tomatoes', 'C',  70, 10, 13);
    l_h := add_harvest(l_esther,  'Roma tomatoes', 'C',  50, 11, 13);

    -- Kijani's other orders
    l_d_onion  := add_demand(l_kijani, 'Onions', 'A', 1200, 60, 19, 'Red onions, medium bulbs');
    l_h := add_harvest(l_samuel, 'Onions', 'A', 700, 12, 16);
    l_h := add_harvest(l_lucy,   'Onions', 'A', 600, 13, 17);

    l_d_pepper := add_demand(l_kijani, 'Green peppers', 'A', 400, 90, 9, 'Firm, no sun scald');
    l_h := add_harvest(l_john, 'Green peppers', 'A', 450, 5, 7);

    l_d_carrot := add_demand(l_kijani, 'Carrots', 'B', 800, 45, 2, 'Washed, tops removed');
    l_h := add_harvest(l_mary,   'Carrots', 'B', 500, -1, 1);
    l_h := add_harvest(l_daniel, 'Carrots', 'B', 400, -1, 1);

    -- One matching pass for everything above
    hl_match_pkg.rematch_all;

    -- Farmers who have already said yes
    confirm(l_d_tomato, l_wanjiru);
    confirm(l_d_tomato, l_peter);
    confirm(l_d_onion,  l_samuel);
    confirm(l_d_onion,  l_lucy);
    confirm(l_d_pepper, l_john);
    confirm(l_d_carrot, l_mary);
    confirm(l_d_carrot, l_daniel);
    update hl_routes set status = 'DISPATCHED' where demand_id = l_d_carrot;  -- in transit

    -- An earlier tomato order, delivered two days ago
    l_d_history := add_demand(l_kijani, 'Roma tomatoes', 'A', 600, 72, -2, 'Weekly restock');
    delivered(l_d_history, add_harvest(l_wanjiru, 'Roma tomatoes', 'A', 350, -6, -4, 'HARVESTED'), 350, l_kijani);
    delivered(l_d_history, add_harvest(l_peter,   'Roma tomatoes', 'A', 250, -6, -4, 'HARVESTED'), 250, l_kijani);
    update hl_demands set status = 'CLOSED' where demand_id = l_d_history;

    hl_match_pkg.g_auto_match := true;
  exception
    when others then
      hl_match_pkg.g_auto_match := true;
      raise;
  end seed;

  procedure reset is
  begin
    hl_match_pkg.g_auto_match := false;
    delete from hl_matches;
    delete from hl_routes;
    delete from hl_demands;
    delete from hl_harvests;
    delete from hl_buyers;
    delete from hl_farmers;
    seed;
    -- Deleting a demo farmer's account (hl_farmer_api.delete_account) also
    -- removes their login mapping; restore it. Dynamic because HL_AUTH is
    -- installed after this package (db/09_auth.sql).
    execute immediate q'[
      begin
        hl_auth.register_user('FARMER_DEMO', 'FARMER', 'Wanjiru Muthoni');
      end;]';
    commit;
  exception
    when others then
      hl_match_pkg.g_auto_match := true;
      raise;
  end reset;

  function featured_demand_id return number is
    l_id hl_demands.demand_id%type;
  begin
    select max(d.demand_id) keep (dense_rank first order by d.need_by_date desc)
      into l_id
      from hl_demands d
      join hl_buyers b on b.buyer_id = d.buyer_id
      join hl_crops c on c.crop_id = d.crop_id
     where b.buyer_name = c_buyer_name
       and c.crop_name = 'Roma tomatoes'
       and d.quantity_kg = 2000;
    return l_id;
  end featured_demand_id;

end hl_demo;
/

begin
  hl_demo.seed;
  commit;
end;
/
