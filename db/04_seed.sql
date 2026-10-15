-- =============================================================================
-- HarvestLink reference data: matching settings and crops.
-- The loss rate and emission factors are published figures; each setting's
-- description names its source. Crop farm-gate prices are FAOSTAT producer
-- prices where FAO publishes one (six of eight crops), otherwise team
-- estimates. Market interview figures (form: Appendix A of
-- docs/HarvestLink_Hackathon_Plan.pdf) replace them through
-- HL_PRICE_OBSERVATIONS and hl_calibration.apply_interview_prices
-- (db/15_market_interviews.sql); each crop records its price basis and source.
-- Sources:
--   [IFPRI 2022] Gatere, Hoffmann, Murphy & Scollard, "Post-harvest Losses and
--     Food Safety in Tomatoes Produced in Laikipia County", IFPRI, 2022:
--     overall loss 28.2% of value, farmer to point of sale (16.4% at farm).
--     https://agris.fao.org/search/en/records/6474812d79cbb2c2c1b91e33 (record)
--     https://cgspace.cgiar.org/server/api/core/bitstreams/38e6297a-b2e1-4294-aea6-8645986e3b1c/content (PDF)
--   [GIZ 2018] Notter & Fussler (INFRAS), "Road transport GHG emission factors
--     for Kenya: pilot study for 2015", short report commissioned by GIZ TraCS
--     with the Kenyan Ministry of Transport, 21 September 2018, Table 2: average
--     CO2 per km of the Kenyan fleet, by vehicle category (HBEFA 3.3 adapted to
--     Kenyan vehicle stock, mileage and traffic data from the University of
--     Nairobi). LCV 216.48 g/km, HGV 759.88 g/km. CO2 only, not CO2e.
--     The report publishes category averages only; factors by size class
--     (e.g. a 5 t rigid truck) are in its Excel annex, "provided separately".
--     Ask GIZ TraCS for them to replace the HGV fleet average.
--     https://changing-transport.org/wp-content/uploads/GIZ_Road-transport-GHG-emission-factors-for-Kenya.pdf
--   [FAOSTAT 2024] FAO, FAOSTAT Prices domain, Producer Price (LCU/tonne),
--     Kenya, annual value 2024, all flagged A (official value); divided by 1,000
--     for KES/kg. Items: Tomatoes (388), Onions and shallots, dry (403),
--     Chillies and peppers, green (401), Carrots and turnips (426), Cabbages
--     (358), Avocados (572). Bulk file Prices_E_Africa.zip, downloaded
--     15 Oct 2026. https://www.fao.org/faostat/en/#data/PP
-- The demo farmers, buyers, harvests and demands are loaded by HL_DEMO
-- (db/08_demo.sql), which can also reset them before a rehearsal.
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
insert into hl_settings values ('TRUCK_CO2_KG_PER_KM',  0.760, 'Truck emissions (kg CO2 per km): Kenyan HGV fleet average 759.88 g/km, 2015 [GIZ 2018]. The average includes 34-40 t trucks, so it overstates a 5 t truck and understates savings');
insert into hl_settings values ('PICKUP_CAPACITY_KG',   1000, 'Pickup hired by an individual farmer');
insert into hl_settings values ('PICKUP_CO2_KG_PER_KM', 0.216, 'Pickup emissions (kg CO2 per km): Kenyan light commercial vehicle fleet average 216.48 g/km, 2015 [GIZ 2018]');
insert into hl_settings values ('BASELINE_LOSS_RATE',   0.28, 'Share of produce lost without a pre-arranged buyer: tomato losses farm to point of sale, 28.2% of value, Laikipia [IFPRI 2022]');
insert into hl_settings values ('ROUTE_START_HOUR',     5,    'Pickup vehicle leaves the buyer at this hour the day before delivery');
insert into hl_settings values ('AVG_SPEED_KMH',        40,   'Average road speed for pickup time estimates (simulated)');
insert into hl_settings values ('STOP_MINUTES',         30,   'Loading time at each farm');

-- ---------------------------------------------------------------------------
-- Crops (KES per kg at farm gate from brokers, and at wholesale market).
-- Broker price: the 2024 farm-gate producer price [FAOSTAT 2024] for
--   tomatoes, onions, green peppers, carrots, cabbage and avocado. FAOSTAT has
--   no Kenyan series for French beans ("Other beans, green" is empty) or kale,
--   so those two are team estimates.
-- Market price: team estimate, farm-gate + 50% for broker margin and
--   transport (rounded to the nearest KES 5); the original estimates for French
--   beans and kale. Not used in any metric.
-- Shelf lives are team estimates.
-- ---------------------------------------------------------------------------
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (1, 'Roma tomatoes',      10, 40.94, 60);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (2, 'Onions',             30, 56.31, 85);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (3, 'Green peppers',      10, 50.08, 75);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (4, 'Carrots',            21, 29.99, 45);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (5, 'Cabbage',            21, 14.44, 20);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (6, 'Hass avocado',       14, 30.89, 45);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (7, 'French beans',        7, 50,    90);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (8, 'Kale (sukuma wiki)',  3, 15,    35);

-- Basis of the prices above (market prices are all team estimates, the default)
update hl_crops
   set broker_price_basis  = 'PUBLISHED',
       broker_price_source = 'FAOSTAT 2024 producer price, Kenya (official)'
 where crop_name in ('Roma tomatoes', 'Onions', 'Green peppers', 'Carrots', 'Cabbage', 'Hass avocado');

-- Advance the identity past the explicit IDs used above
alter table hl_crops modify crop_id generated by default on null as identity (start with limit value);

-- ---------------------------------------------------------------------------
-- Sign-up consent notice (shown before a farmer registers). Draft wording:
-- have it reviewed before real farmers sign up.
-- ---------------------------------------------------------------------------
insert into hl_consent_texts (consent_version, consent_text) values ('2026-10-v1',
  'HarvestLink keeps your name, phone number, farm location, cooperative and expected harvests '
  || 'so it can match you with buyers and plan pickups. Buyers see your name, area and harvest; '
  || 'they see your phone number only after you accept their offer. When you accept, reject or '
  || 'deliver an order, the agreed terms (your name, the buyer, crop, grade, kg and price) are '
  || 'written to a tamper-proof agreement record. You can ask for a copy of your data or delete '
  || 'your account at any time. Deleting removes your profile, harvests and open offers at once; '
  || 'agreement records already written cannot be changed and are kept for at least 16 days, and '
  || 'new records about your past orders show you only as an erased farmer.');

commit;
