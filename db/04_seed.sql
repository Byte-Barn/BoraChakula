-- =============================================================================
-- HarvestLink demo seed data
-- Farmers and buyers are fictional. Coordinates are approximate town centres
-- in Murang'a, Kiambu and Nairobi counties. Prices and loss rates are
-- placeholders: replace them with figures from the market interviews.
-- Dates are relative to today so the demo always looks current.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
insert into hl_settings values ('WEIGHT_QUANTITY',      0.25, 'Matching weight: share of the order one farmer can fill');
insert into hl_settings values ('WEIGHT_GRADE',         0.25, 'Matching weight: grade fit');
insert into hl_settings values ('WEIGHT_TIMING',        0.25, 'Matching weight: harvest timing vs need-by date');
insert into hl_settings values ('WEIGHT_DISTANCE',      0.25, 'Matching weight: proximity to delivery point');
insert into hl_settings values ('MAX_DISTANCE_KM',      200,  'Farms further than this (road km) are not matched');
insert into hl_settings values ('ROAD_FACTOR',          1.3,  'Road distance / straight-line distance');
insert into hl_settings values ('TRUCK_CAPACITY_KG',    5000, 'Shared aggregation truck payload');
insert into hl_settings values ('TRUCK_CO2_KG_PER_KM',  0.7,  'Medium truck emissions (kg CO2 per km)');
insert into hl_settings values ('PICKUP_CAPACITY_KG',   1000, 'Pickup hired by an individual farmer');
insert into hl_settings values ('PICKUP_CO2_KG_PER_KM', 0.25, 'Pickup emissions (kg CO2 per km)');
insert into hl_settings values ('BASELINE_LOSS_RATE',   0.30, 'Share of produce lost without a pre-arranged buyer');

-- ---------------------------------------------------------------------------
-- Crops (KES per kg)
-- ---------------------------------------------------------------------------
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (1, 'Tomatoes',     10, 35, 60);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (2, 'Hass Avocado', 14, 20, 45);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (3, 'Cabbage',      21, 10, 25);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (4, 'Bananas',       7, 20, 40);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (5, 'French Beans',  7, 50, 90);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (6, 'Kale (Sukuma Wiki)', 3, 15, 35);

-- ---------------------------------------------------------------------------
-- Farmers (fictional)
-- ---------------------------------------------------------------------------
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 1, 'Mary Wanjiku',   '+254700000001', 'Murang''a', 'Kangema',  -0.6833, 36.9667, 'Kangema Horticulture Coop', 'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 2, 'Peter Kamau',    '+254700000002', 'Murang''a', 'Kiriaini', -0.6200, 36.9300, 'Kangema Horticulture Coop', 'N', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 3, 'Grace Njeri',    '+254700000003', 'Murang''a', 'Kiharu',   -0.7167, 37.1500, null,                        'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 4, 'John Mwangi',    '+254700000004', 'Murang''a', 'Kahuro',   -0.7000, 37.0833, 'Kahuro Avocado Growers',    'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 5, 'Esther Wairimu', '+254700000005', 'Murang''a', 'Kigumo',   -0.8167, 37.0167, 'Kigumo Farmers Coop',       'N', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 6, 'Samuel Kariuki', '+254700000006', 'Murang''a', 'Kandara',  -0.9000, 37.0000, null,                        'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 7, 'Lucy Muthoni',   '+254700000007', 'Murang''a', 'Gatanga',  -0.9500, 37.0300, 'Gatanga Fruit Growers',     'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 8, 'David Ndungu',   '+254700000008', 'Murang''a', 'Maragua',  -0.7953, 37.1322, null,                        'N', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values ( 9, 'Jane Wambui',    '+254700000009', 'Murang''a', 'Kenol',    -0.8550, 37.1350, 'Kigumo Farmers Coop',       'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (10, 'Joseph Githinji','+254700000010', 'Murang''a', 'Kabati',   -0.8500, 37.0700, null,                        'N', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (11, 'Ann Nyambura',   '+254700000011', 'Murang''a', 'Kangema',  -0.6900, 36.9750, 'Kangema Horticulture Coop', 'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (12, 'Francis Maina',  '+254700000012', 'Murang''a', 'Kahuro',   -0.7050, 37.0900, 'Kahuro Avocado Growers',    'N', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (13, 'Ruth Wangari',   '+254700000013', 'Murang''a', 'Kigumo',   -0.8100, 37.0250, 'Kigumo Farmers Coop',       'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (14, 'Daniel Mbugua',  '+254700000014', 'Murang''a', 'Maragua',  -0.7900, 37.1400, null,                        'Y', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (15, 'Agnes Wanjiru',  '+254700000015', 'Murang''a', 'Gatanga',  -0.9550, 37.0400, 'Gatanga Fruit Growers',     'N', 'Y');
insert into hl_farmers (farmer_id, full_name, phone, county, location_name, latitude, longitude, cooperative, has_smartphone, consent_given) values (16, 'Paul Kinyua',    '+254700000016', 'Murang''a', 'Kandara',  -0.8950, 37.0100, null,                        'Y', 'Y');

-- ---------------------------------------------------------------------------
-- Buyers (fictional)
-- ---------------------------------------------------------------------------
insert into hl_buyers (buyer_id, buyer_name, buyer_type, contact_phone, contact_email, county, location_name, latitude, longitude, accepted_grades, kra_pin, is_verified) values (1, 'Mwangaza Fresh Supermarkets',       'RETAILER',         '+254711000001', 'procurement@mwangaza.example', 'Nairobi',   'Nairobi CBD',  -1.2864, 36.8172, 'A',     'P000000001A', 'Y');
insert into hl_buyers (buyer_id, buyer_name, buyer_type, contact_phone, contact_email, county, location_name, latitude, longitude, accepted_grades, kra_pin, is_verified) values (2, 'Kijani Exports Ltd',                'EXPORTER',         '+254711000002', 'sourcing@kijani.example',      'Nairobi',   'Embakasi',     -1.3192, 36.9278, 'A',     'P000000002B', 'Y');
insert into hl_buyers (buyer_id, buyer_name, buyer_type, contact_phone, contact_email, county, location_name, latitude, longitude, accepted_grades, kra_pin, is_verified) values (3, 'Thika Agro Processors',             'PROCESSOR',        '+254711000003', 'intake@thikaagro.example',     'Kiambu',    'Thika',        -1.0333, 37.0693, 'B,C',   'P000000003C', 'Y');
insert into hl_buyers (buyer_id, buyer_name, buyer_type, contact_phone, contact_email, county, location_name, latitude, longitude, accepted_grades, kra_pin, is_verified) values (4, 'Murang''a Schools Feeding Programme','SCHOOL',           '+254711000004', 'meals@schools.example',        'Murang''a', 'Murang''a Town', -0.7210, 37.1526, 'A,B', null,          'Y');
insert into hl_buyers (buyer_id, buyer_name, buyer_type, contact_phone, contact_email, county, location_name, latitude, longitude, accepted_grades, kra_pin, is_verified) values (5, 'Wakulima Traders Group',            'WHOLESALE_MARKET', '+254711000005', 'orders@wakulima.example',      'Nairobi',   'Marikiti',     -1.2833, 36.8283, 'A,B,C', 'P000000005E', 'Y');
insert into hl_buyers (buyer_id, buyer_name, buyer_type, contact_phone, contact_email, county, location_name, latitude, longitude, accepted_grades, kra_pin, is_verified) values (6, 'Savanna Hotels Group',              'HOTEL',            '+254711000006', 'chef@savanna.example',         'Nairobi',   'Westlands',    -1.2676, 36.8108, 'A,B',   'P000000006F', 'N');

-- ---------------------------------------------------------------------------
-- Expected harvests (dates relative to today)
-- ---------------------------------------------------------------------------
-- Tomatoes
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 1,  1, 1, 'A',  800, trunc(sysdate) + 9,  trunc(sysdate) + 12);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 2,  2, 1, 'A',  450, trunc(sysdate) + 10, trunc(sysdate) + 13);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 3,  5, 1, 'A',  600, trunc(sysdate) + 8,  trunc(sysdate) + 11);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 4, 13, 1, 'B',  700, trunc(sysdate) + 8,  trunc(sysdate) + 11);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 5, 10, 1, 'A',  500, trunc(sysdate) + 11, trunc(sysdate) + 14);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 6,  6, 1, 'C',  900, trunc(sysdate) + 7,  trunc(sysdate) + 10);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 7, 16, 1, 'C',  400, trunc(sysdate) + 9,  trunc(sysdate) + 11);
-- Hass Avocado
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 8,  4, 2, 'A', 1200, trunc(sysdate) + 12, trunc(sysdate) + 16);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values ( 9, 12, 2, 'A',  900, trunc(sysdate) + 13, trunc(sysdate) + 16);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (10,  1, 2, 'A',  500, trunc(sysdate) + 10, trunc(sysdate) + 14);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (11, 11, 2, 'B',  700, trunc(sysdate) + 11, trunc(sysdate) + 15);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (12,  3, 2, 'A',  600, trunc(sysdate) + 14, trunc(sysdate) + 17);
-- Cabbage
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (13,  8, 3, 'B',  900, trunc(sysdate) + 5,  trunc(sysdate) + 8);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (14, 14, 3, 'A',  400, trunc(sysdate) + 6,  trunc(sysdate) + 9);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (15,  9, 3, 'B',  500, trunc(sysdate) + 4,  trunc(sysdate) + 7);
-- Bananas
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (16,  7, 4, 'B', 1100, trunc(sysdate) + 5,  trunc(sysdate) + 8);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (17, 15, 4, 'A',  800, trunc(sysdate) + 6,  trunc(sysdate) + 8);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (18,  5, 4, 'B',  600, trunc(sysdate) + 4,  trunc(sysdate) + 7);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (19, 10, 4, 'C',  500, trunc(sysdate) + 5,  trunc(sysdate) + 7);
-- French Beans
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (20,  2, 5, 'A',  250, trunc(sysdate) + 4,  trunc(sysdate) + 6);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (21, 11, 5, 'A',  200, trunc(sysdate) + 5,  trunc(sysdate) + 6);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (22,  6, 5, 'B',  300, trunc(sysdate) + 4,  trunc(sysdate) + 6);
-- Kale (no demand yet: shows up in grade routing)
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (23,  3, 6, 'A',  300, trunc(sysdate) + 2,  trunc(sysdate) + 3);
insert into hl_harvests (harvest_id, farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to) values (24, 14, 6, 'B',  250, trunc(sysdate) + 2,  trunc(sysdate) + 4);

-- ---------------------------------------------------------------------------
-- Buyer demands
-- ---------------------------------------------------------------------------
insert into hl_demands (demand_id, buyer_id, crop_id, grade_required, quantity_kg, price_per_kg, need_by_date, notes) values (1, 1, 1, 'A', 2000,  70, trunc(sysdate) + 14, 'Weekly tomato supply for 4 Nairobi branches');
insert into hl_demands (demand_id, buyer_id, crop_id, grade_required, quantity_kg, price_per_kg, need_by_date, notes) values (2, 2, 2, 'A', 3000,  45, trunc(sysdate) + 18, 'Export consignment, sea freight to Rotterdam');
insert into hl_demands (demand_id, buyer_id, crop_id, grade_required, quantity_kg, price_per_kg, need_by_date, notes) values (3, 4, 3, 'B', 1500,  22, trunc(sysdate) + 10, 'School lunches, two weeks');
insert into hl_demands (demand_id, buyer_id, crop_id, grade_required, quantity_kg, price_per_kg, need_by_date, notes) values (4, 3, 1, 'C', 1200,  25, trunc(sysdate) + 12, 'Tomato paste line; blemished produce accepted');
insert into hl_demands (demand_id, buyer_id, crop_id, grade_required, quantity_kg, price_per_kg, need_by_date, notes) values (5, 5, 4, 'B', 2500,  35, trunc(sysdate) + 9,  'Marikiti wholesale stall');
insert into hl_demands (demand_id, buyer_id, crop_id, grade_required, quantity_kg, price_per_kg, need_by_date, notes) values (6, 6, 5, 'A',  600, 110, trunc(sysdate) + 7,  'Hotel kitchens, fine beans');

-- Advance identity sequences past the explicit IDs used above
alter table hl_crops    modify crop_id    generated by default on null as identity (start with limit value);
alter table hl_farmers  modify farmer_id  generated by default on null as identity (start with limit value);
alter table hl_buyers   modify buyer_id   generated by default on null as identity (start with limit value);
alter table hl_harvests modify harvest_id generated by default on null as identity (start with limit value);
alter table hl_demands  modify demand_id  generated by default on null as identity (start with limit value);

commit;

-- Generate matches, routes and impact numbers for all demands
begin
  hl_match_pkg.run_all_open;
  commit;
end;
/
