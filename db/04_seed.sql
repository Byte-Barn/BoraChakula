-- =============================================================================
-- HarvestLink reference data: matching settings and crops.
-- The loss rate and emission factors are published figures; each setting's
-- description names its source. Crop farm-gate prices are FAOSTAT producer
-- prices where FAO publishes one, otherwise team estimates; replace them with
-- figures from the market interviews (form: Appendix A of
-- docs/HarvestLink_Hackathon_Plan.pdf) when available.
-- Sources:
--   [IFPRI 2022] Gatere, Hoffmann, Murphy & Scollard, "Post-harvest Losses and
--     Food Safety in Tomatoes Produced in Laikipia County", IFPRI, 2022:
--     overall loss 28.2% of value, farmer to point of sale (16.4% at farm).
--     https://agris.fao.org/search/en/records/6474812d79cbb2c2c1b91e33 (record)
--     https://cgspace.cgiar.org/server/api/core/bitstreams/38e6297a-b2e1-4294-aea6-8645986e3b1c/content (PDF)
--   [DESNZ 2024] UK Department for Energy Security and Net Zero, Greenhouse gas
--     reporting: conversion factors 2024 (condensed set v1.1), sheet
--     "Freighting goods", diesel, kg CO2e per km. UK fleet averages, used as a
--     proxy until Kenyan factors are available.
--     https://www.gov.uk/government/publications/greenhouse-gas-reporting-conversion-factors-2024
--   [FAOSTAT 2024] FAO, FAOSTAT Producer Prices, Kenya, as republished in KES/kg
--     (price as of January 2024) by Selina Wamucii market insights, e.g.
--     https://www.selinawamucii.com/insights/prices/kenya/tomatoes/
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
insert into hl_settings values ('TRUCK_CO2_KG_PER_KM',  0.595, 'Medium truck emissions (kg CO2e per km): diesel rigid HGV 7.5-17 t, average laden [DESNZ 2024]');
insert into hl_settings values ('PICKUP_CAPACITY_KG',   1000, 'Pickup hired by an individual farmer');
insert into hl_settings values ('PICKUP_CO2_KG_PER_KM', 0.25, 'Pickup emissions (kg CO2e per km): average diesel van up to 3.5 t, 0.250 [DESNZ 2024]');
insert into hl_settings values ('BASELINE_LOSS_RATE',   0.28, 'Share of produce lost without a pre-arranged buyer: tomato losses farm to point of sale, 28.2% of value, Laikipia [IFPRI 2022]');
insert into hl_settings values ('ROUTE_START_HOUR',     5,    'Pickup vehicle leaves the buyer at this hour the day before delivery');
insert into hl_settings values ('AVG_SPEED_KMH',        40,   'Average road speed for pickup time estimates (simulated)');
insert into hl_settings values ('STOP_MINUTES',         30,   'Loading time at each farm');

-- ---------------------------------------------------------------------------
-- Crops (KES per kg at farm gate from brokers, and at wholesale market).
-- Broker price: the farm-gate producer price [FAOSTAT 2024] for tomatoes,
--   onions, carrots, cabbage and avocado (the republisher marks avocado as
--   estimated); peppers, French beans and kale have none, so those are team
--   estimates.
-- Market price: team estimate, farm-gate + 50% for broker margin and
--   transport (rounded to KES 5); the original estimates for crops without a
--   FAOSTAT price. Not used in any metric.
-- Shelf lives are team estimates.
-- ---------------------------------------------------------------------------
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (1, 'Roma tomatoes',      10, 42.17, 65);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (2, 'Onions',             30, 58.01, 85);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (3, 'Green peppers',      10, 45,    80);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (4, 'Carrots',            21, 30.89, 45);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (5, 'Cabbage',            21, 14.88, 25);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (6, 'Hass avocado',       14, 19,    30);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (7, 'French beans',        7, 50,    90);
insert into hl_crops (crop_id, crop_name, shelf_life_days, typical_broker_price_kg, typical_market_price_kg) values (8, 'Kale (sukuma wiki)',  3, 15,    35);

-- Advance the identity past the explicit IDs used above
alter table hl_crops modify crop_id generated by default on null as identity (start with limit value);

commit;
