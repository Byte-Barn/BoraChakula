-- =============================================================================
-- HarvestLink reporting views (sources for APEX pages, maps and dashboard)
-- =============================================================================

-- Harvest supply with remaining unallocated volume
create or replace view hl_harvest_availability_v as
select h.harvest_id,
       h.farmer_id,
       f.full_name          as farmer_name,
       f.location_name,
       f.county,
       f.latitude,
       f.longitude,
       h.crop_id,
       c.crop_name,
       h.grade,
       h.expected_qty_kg,
       h.expected_qty_kg - nvl(a.allocated_kg, 0) as available_kg,
       h.harvest_from,
       h.harvest_to,
       h.status
  from hl_harvests h
  join hl_farmers f on f.farmer_id = h.farmer_id
  join hl_crops c on c.crop_id = h.crop_id
  left join (select harvest_id, sum(allocated_kg) as allocated_kg
               from hl_matches
              where status <> 'REJECTED'
              group by harvest_id) a
    on a.harvest_id = h.harvest_id;

-- Buyer demands with fill progress and logistics savings
create or replace view hl_demand_summary_v as
select d.demand_id,
       d.buyer_id,
       b.buyer_name,
       b.buyer_type,
       b.is_verified,
       c.crop_name,
       d.grade_required,
       d.quantity_kg,
       d.price_per_kg,
       d.need_by_date,
       d.status,
       nvl(m.allocated_kg, 0)                          as allocated_kg,
       round(100 * nvl(m.allocated_kg, 0) / d.quantity_kg, 1) as fill_pct,
       nvl(m.farmers, 0)                               as farmers_matched,
       r.vehicle_type,
       r.trips,
       r.aggregated_km,
       r.individual_km,
       r.individual_km - r.aggregated_km               as km_saved,
       r.individual_co2_kg - r.aggregated_co2_kg       as co2_saved_kg,
       r.route_sequence
  from hl_demands d
  join hl_buyers b on b.buyer_id = d.buyer_id
  join hl_crops c on c.crop_id = d.crop_id
  left join (select mm.demand_id,
                    sum(mm.allocated_kg)         as allocated_kg,
                    count(distinct h.farmer_id)  as farmers
               from hl_matches mm
               join hl_harvests h on h.harvest_id = mm.harvest_id
              where mm.status <> 'REJECTED'
              group by mm.demand_id) m
    on m.demand_id = d.demand_id
  left join hl_routes r on r.demand_id = d.demand_id;

-- One row per match with farmer and buyer coordinates (APEX Map region)
create or replace view hl_match_detail_v as
select m.match_id,
       m.demand_id,
       m.harvest_id,
       m.stop_order,
       m.status,
       m.allocated_kg,
       m.distance_km,
       m.score_total,
       m.score_quantity,
       m.score_grade,
       m.score_timing,
       m.score_distance,
       m.match_reason,
       f.farmer_id,
       f.full_name     as farmer_name,
       f.phone         as farmer_phone,
       f.location_name as farmer_location,
       f.latitude      as farmer_lat,
       f.longitude     as farmer_lon,
       h.grade,
       c.crop_name,
       b.buyer_name,
       nvl(d.delivery_lat, b.latitude)  as delivery_lat,
       nvl(d.delivery_lon, b.longitude) as delivery_lon
  from hl_matches m
  join hl_harvests h on h.harvest_id = m.harvest_id
  join hl_farmers f on f.farmer_id = h.farmer_id
  join hl_crops c on c.crop_id = h.crop_id
  join hl_demands d on d.demand_id = m.demand_id
  join hl_buyers b on b.buyer_id = d.buyer_id;

-- Grade routing: where unallocated produce should go, and the best buyer
-- that accepts its grade (right channel first, then nearest), so no grade
-- is left without an outlet
create or replace view hl_grade_routing_v as
select a.harvest_id,
       a.farmer_name,
       a.location_name,
       a.crop_name,
       a.grade,
       a.available_kg,
       a.harvest_from,
       a.harvest_to,
       case a.grade
         when 'A' then 'Premium retail / export'
         when 'B' then 'Wholesale markets, schools, hotels'
         else 'Processors (juice, puree, flour, animal feed)'
       end as recommended_channel,
       nb.buyer_name   as suggested_buyer,
       nb.buyer_type   as suggested_buyer_type,
       nb.distance_km  as suggested_buyer_km
  from hl_harvest_availability_v a
  outer apply (
        select b.buyer_name,
               b.buyer_type,
               hl_match_pkg.distance_km(a.latitude, a.longitude, b.latitude, b.longitude) as distance_km
          from hl_buyers b
         where instr(',' || b.accepted_grades || ',', ',' || a.grade || ',') > 0
         order by case
                    when a.grade = 'A' and b.buyer_type in ('RETAILER', 'EXPORTER') then 0
                    when a.grade = 'B' and b.buyer_type in ('WHOLESALE_MARKET', 'SCHOOL', 'HOTEL') then 0
                    when a.grade = 'C' and b.buyer_type = 'PROCESSOR' then 0
                    else 1
                  end,
                  distance_km
         fetch first 1 row only
       ) nb
 where a.available_kg > 0
   and a.status in ('OPEN', 'PARTIAL');

-- Headline impact numbers for the dashboard and pitch
create or replace view hl_impact_v as
with alloc as (
  select m.allocated_kg,
         h.farmer_id,
         h.grade,
         d.demand_id,
         d.price_per_kg,
         c.typical_broker_price_kg
    from hl_matches m
    join hl_harvests h on h.harvest_id = m.harvest_id
    join hl_demands d on d.demand_id = m.demand_id
    join hl_crops c on c.crop_id = d.crop_id
   where m.status <> 'REJECTED'
)
select (select nvl(sum(allocated_kg), 0) from alloc)                    as total_matched_kg,
       (select count(distinct farmer_id) from alloc)                    as farmers_matched,
       (select count(distinct demand_id) from alloc)                    as demands_served,
       (select round(nvl(sum(allocated_kg), 0)
                     * hl_match_pkg.get_setting('BASELINE_LOSS_RATE'), 0)
          from alloc)                                                   as loss_avoided_kg,
       (select round(nvl(sum(individual_km - aggregated_km), 0), 0)
          from hl_routes)                                               as km_saved,
       (select round(nvl(sum(individual_co2_kg - aggregated_co2_kg), 0), 0)
          from hl_routes)                                               as co2_saved_kg,
       -- Grade C usually goes unsold, so its baseline price is zero
       (select round(nvl(sum(allocated_kg
                             * greatest(price_per_kg - case grade when 'C' then 0
                                                       else typical_broker_price_kg end, 0)), 0), 0)
          from alloc)                                                   as farmer_income_uplift_kes
  from dual;
