-- HarvestLink: pickup route views for the logistics screen.
--
-- HL_MATCH_PKG.PLAN_ROUTE writes HL_ROUTE_STOPS whenever matching runs. These
-- views shape them for an APEX Map region (points and line layers) and the
-- stops table. Distances are straight-line x ROAD_FACTOR and times use
-- AVG_SPEED_KMH / STOP_MINUTES: label both as simulated.

-- One row per stop: pins, the stops table, and for each farm its direct
-- distance to the buyer (the dashed "separate trips" comparison lines)
create or replace view hl_route_stop_v as
select r.route_id,
       r.demand_id,
       r.vehicle_type,
       r.status                                        as route_status,
       s.stop_no,
       s.stop_type,
       s.match_id,
       s.stop_name,
       s.place,
       s.latitude,
       s.longitude,
       s.load_kg,
       s.leg_km,
       s.cumulative_km,
       s.arrive_at,
       case when m.match_id is null      then null
            when m.status = 'PROPOSED'  then 'PENDING'
            when m.status = 'REJECTED'  then 'DECLINED'
            else 'MATCHED'
       end                                             as ui_status,
       d.latitude                                      as dest_lat,
       d.longitude                                     as dest_lon,
       case when s.stop_type = 'FARM'
            then hl_match_pkg.distance_km(s.latitude, s.longitude, d.latitude, d.longitude)
       end                                             as direct_km,
       'simulated'                                     as provenance
  from hl_routes r
  join hl_route_stops s on s.route_id = r.route_id
  join hl_route_stops d on d.route_id = r.route_id and d.stop_type = 'DESTINATION'
  left join hl_matches m on m.match_id = s.match_id;

-- The shared trip as a GeoJSON LineString (buyer -> farms -> buyer), for an
-- APEX Map line layer, with its totals
create or replace view hl_route_line_v as
with pts as (
  select s.route_id, s.stop_no,
         '[' || to_char(s.longitude, 'fm990.000000', 'nls_numeric_characters=''.,''') || ','
             || to_char(s.latitude,  'fm990.000000', 'nls_numeric_characters=''.,''') || ']' as pt
    from hl_route_stops s
)
select r.route_id,
       r.demand_id,
       r.vehicle_type,
       r.trips,
       r.stops,
       r.aggregated_km,
       r.individual_km,
       r.individual_km - r.aggregated_km                             as km_saved,
       r.individual_co2_kg - r.aggregated_co2_kg                     as co2_saved_kg,
       (select max(arrive_at) from hl_route_stops s
         where s.route_id = r.route_id and s.stop_type = 'FARM')    as last_pickup_at,
       (select arrive_at from hl_route_stops s
         where s.route_id = r.route_id and s.stop_type = 'DESTINATION') as delivered_at,
       '{"type":"LineString","coordinates":['
         || (select p.pt from pts p
              where p.route_id = r.route_id
                and p.stop_no = (select max(stop_no) from hl_route_stops x where x.route_id = r.route_id))
         || ','
         || (select listagg(p.pt, ',') within group (order by p.stop_no)
               from pts p where p.route_id = r.route_id)
         || ']}'                                                     as route_geojson,
       'simulated'                                                   as provenance
  from hl_routes r
 where exists (select 1 from hl_route_stops s where s.route_id = r.route_id);
