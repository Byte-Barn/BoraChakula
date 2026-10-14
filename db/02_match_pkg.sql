-- =============================================================================
-- HL_MATCH_PKG: HarvestLink matching, aggregation and route planning engine
--
-- For a buyer demand the engine:
--   1. finds eligible harvests (same crop, grade at least as good as required,
--      ready before the need-by date and still fresh, within max distance),
--   2. scores each on quantity fit, grade fit, timing and distance (0..1),
--   3. allocates volume to the best-scoring farmers until the order is filled
--      (aggregating many smallholders into one order),
--   4. plans one shared pickup route (nearest-neighbour), using whichever
--      vehicle emits less for the load, and records the km and CO2 saved
--      against every farmer travelling alone.
-- =============================================================================

create or replace package hl_match_pkg as

  -- Automatic re-matching from the HL_*_AUTO_MATCH triggers. Bulk loaders
  -- (HL_DEMO) switch it off for the session, then match once at the end.
  g_auto_match boolean := true;

  function get_setting (p_key in varchar2) return number;

  -- Road distance estimate: great-circle distance x road winding factor
  function distance_km (
    p_lat1 in number, p_lon1 in number,
    p_lat2 in number, p_lon2 in number
  ) return number;

  -- Volume of a harvest not yet promised to a (non-rejected) match or
  -- allocated to an outlet (HL_ALLOCATIONS)
  function available_kg (p_harvest_id in number) return number;

  -- Score components: return null when the harvest is not eligible
  function grade_score (p_harvest_grade in varchar2, p_required_grade in varchar2) return number;
  function timing_score (
    p_harvest_from in date, p_harvest_to in date,
    p_need_by in date, p_shelf_life_days in number
  ) return number;
  function distance_score (p_distance_km in number) return number;

  procedure run_matching (p_demand_id in number);
  procedure run_all_open;
  -- Clears all proposals for active demands and re-matches them in deadline
  -- order, so results do not depend on which record changed last
  procedure rematch_all;
  procedure plan_route (p_demand_id in number);
  procedure refresh_statuses (p_demand_id in number);

  procedure accept_match (p_match_id in number);
  procedure reject_match (p_match_id in number);

  -- Frontend contract (docs/backend-api.md). Each commits nothing: APEX
  -- commits at the end of the page process.
  -- run:        re-match one demand now (e.g. "Run matching again")
  procedure run (p_demand_id in number);
  -- confirm:    the farmer said yes; appends ACCEPTED to the agreement ledger
  procedure confirm (p_match_id in number);
  -- decline:    the farmer said no; that farm is skipped for this demand and
  --             the shortfall is re-matched from other farms
  procedure decline (p_match_id in number);
  -- rerun_open: re-match every active demand, earliest deadline first
  procedure rerun_open;

end hl_match_pkg;
/

create or replace package body hl_match_pkg as

  c_earth_radius_km constant number := 6371;

  function get_setting (p_key in varchar2) return number is
    l_value hl_settings.setting_value%type;
  begin
    select setting_value into l_value from hl_settings where setting_key = p_key;
    return l_value;
  exception
    when no_data_found then
      raise_application_error(-20100, 'Missing HarvestLink setting: ' || p_key);
  end get_setting;

  function distance_km (
    p_lat1 in number, p_lon1 in number,
    p_lat2 in number, p_lon2 in number
  ) return number is
    l_rad  constant number := acos(-1) / 180;
    l_dlat number := (p_lat2 - p_lat1) * l_rad;
    l_dlon number := (p_lon2 - p_lon1) * l_rad;
    l_a    number;
  begin
    l_a := power(sin(l_dlat / 2), 2)
         + cos(p_lat1 * l_rad) * cos(p_lat2 * l_rad) * power(sin(l_dlon / 2), 2);
    return round(2 * c_earth_radius_km * asin(least(1, sqrt(l_a)))
                 * get_setting('ROAD_FACTOR'), 2);
  end distance_km;

  function available_kg (p_harvest_id in number) return number is
    l_available number;
  begin
    select h.expected_qty_kg
           - nvl((select sum(m.allocated_kg) from hl_matches m
                   where m.harvest_id = h.harvest_id and m.status <> 'REJECTED'), 0)
           - nvl((select sum(a.alloc_kg) from hl_allocations a
                   where a.harvest_id = h.harvest_id), 0)
      into l_available
      from hl_harvests h
     where h.harvest_id = p_harvest_id;
    return greatest(l_available, 0);
  end available_kg;

  -- Grades: A best, C lowest. A better grade satisfies a lower requirement,
  -- but scores less so premium produce is kept for premium buyers.
  function grade_score (p_harvest_grade in varchar2, p_required_grade in varchar2) return number is
    l_gap pls_integer := ascii(p_required_grade) - ascii(p_harvest_grade);
  begin
    return case
             when l_gap < 0 then null
             when l_gap = 0 then 1
             when l_gap = 1 then 0.7
             else 0.5
           end;
  end grade_score;

  -- Harvest must start by the need-by date and the produce must still be
  -- fresh on delivery. Harvesting closer to the need-by date scores higher.
  function timing_score (
    p_harvest_from in date, p_harvest_to in date,
    p_need_by in date, p_shelf_life_days in number
  ) return number is
    l_days_early number;
  begin
    if p_harvest_from > p_need_by then
      return null;
    elsif p_harvest_to > p_need_by then
      return 0.9;  -- window straddles the need-by date: pick the early part
    end if;
    l_days_early := p_need_by - p_harvest_to;
    if l_days_early > p_shelf_life_days then
      return null;
    end if;
    return round(1 - l_days_early / p_shelf_life_days, 4);
  end timing_score;

  function distance_score (p_distance_km in number) return number is
    l_max number := get_setting('MAX_DISTANCE_KM');
  begin
    if p_distance_km > l_max then
      return null;
    end if;
    return round(1 - p_distance_km / l_max, 4);
  end distance_score;

  procedure refresh_statuses (p_demand_id in number) is
  begin
    update hl_demands d
       set d.status = (
             select case
                      when nvl(sum(m.allocated_kg), 0) >= d.quantity_kg then 'FILLED'
                      when nvl(sum(m.allocated_kg), 0) > 0 then 'PARTIAL'
                      else 'OPEN'
                    end
               from hl_matches m
              where m.demand_id = d.demand_id
                and m.status <> 'REJECTED')
     where d.demand_id = p_demand_id
       and d.status in ('OPEN', 'PARTIAL', 'FILLED');

    update hl_harvests h
       set h.status = (
             select case
                      when nvl(sum(m.allocated_kg), 0) >= h.expected_qty_kg then 'COMMITTED'
                      when nvl(sum(m.allocated_kg), 0) > 0 then 'PARTIAL'
                      else 'OPEN'
                    end
               from hl_matches m
              where m.harvest_id = h.harvest_id
                and m.status <> 'REJECTED')
     where h.status in ('OPEN', 'PARTIAL', 'COMMITTED')
       and h.crop_id = (select crop_id from hl_demands where demand_id = p_demand_id);
  end refresh_statuses;

  procedure plan_route (p_demand_id in number) is
    type t_stop is record (
      match_id  hl_matches.match_id%type,
      lat       number,
      lon       number,
      qty       number,
      name      varchar2(150),
      place     varchar2(100)
    );
    type t_stops is table of t_stop index by pls_integer;
    type t_flags is table of boolean index by pls_integer;

    l_stops         t_stops;
    l_visited       t_flags;
    l_dest_lat      number;
    l_dest_lon      number;
    l_cur_lat       number;
    l_cur_lon       number;
    l_best          pls_integer;
    l_best_km       number;
    l_km            number;
    l_tour_km       number := 0;
    l_individual_km number := 0;
    l_total_kg      number := 0;
    l_direct_trips  number := 0;
    l_truck_trips   number;
    l_pickup_trips  number;
    l_vehicle       varchar2(10);
    l_trips         number;
    l_co2_per_km    number;
    l_stop_count    pls_integer;
    l_sequence      varchar2(4000);
    l_locked        number;
  begin
    select count(*) into l_locked
      from hl_routes
     where demand_id = p_demand_id
       and status <> 'PLANNED';
    if l_locked > 0 then
      return;  -- route already dispatched; do not re-plan
    end if;

    delete from hl_routes where demand_id = p_demand_id;

    select nvl(d.delivery_lat, b.latitude), nvl(d.delivery_lon, b.longitude)
      into l_dest_lat, l_dest_lon
      from hl_demands d
      join hl_buyers b on b.buyer_id = d.buyer_id
     where d.demand_id = p_demand_id;

    select m.match_id, f.latitude, f.longitude, m.allocated_kg, f.full_name, f.location_name
      bulk collect into l_stops
      from hl_matches m
      join hl_harvests h on h.harvest_id = m.harvest_id
      join hl_farmers f on f.farmer_id = h.farmer_id
     where m.demand_id = p_demand_id
       and m.status <> 'REJECTED';

    if l_stops.count = 0 then
      return;
    end if;

    -- Baseline: every farmer hires their own pickup, round trip to the buyer
    for i in 1 .. l_stops.count loop
      l_visited(i) := false;
      l_total_kg := l_total_kg + l_stops(i).qty;
      l_direct_trips := l_direct_trips + ceil(l_stops(i).qty / get_setting('PICKUP_CAPACITY_KG'));
      l_individual_km := l_individual_km
        + 2 * distance_km(l_stops(i).lat, l_stops(i).lon, l_dest_lat, l_dest_lon)
            * ceil(l_stops(i).qty / get_setting('PICKUP_CAPACITY_KG'));
    end loop;

    -- Shared truck: leave the buyer, visit nearest unvisited farm, return
    l_cur_lat := l_dest_lat;
    l_cur_lon := l_dest_lon;
    for step in 1 .. l_stops.count loop
      l_best := null;
      l_best_km := null;
      for i in 1 .. l_stops.count loop
        if not l_visited(i) then
          l_km := distance_km(l_cur_lat, l_cur_lon, l_stops(i).lat, l_stops(i).lon);
          if l_best_km is null or l_km < l_best_km then
            l_best := i;
            l_best_km := l_km;
          end if;
        end if;
      end loop;

      l_visited(l_best) := true;
      l_tour_km := l_tour_km + l_best_km;
      l_cur_lat := l_stops(l_best).lat;
      l_cur_lon := l_stops(l_best).lon;

      update hl_matches set stop_order = step where match_id = l_stops(l_best).match_id;
      l_sequence := substr(l_sequence
        || case when step > 1 then ' > ' end
        || l_stops(l_best).name || ' (' || l_stops(l_best).place || ')', 1, 4000);
    end loop;
    l_tour_km := l_tour_km + distance_km(l_cur_lat, l_cur_lon, l_dest_lat, l_dest_lon);

    -- Small loads go by pickup; pick whichever fleet emits less on this tour
    l_truck_trips  := ceil(l_total_kg / get_setting('TRUCK_CAPACITY_KG'));
    l_pickup_trips := ceil(l_total_kg / get_setting('PICKUP_CAPACITY_KG'));
    if l_pickup_trips * get_setting('PICKUP_CO2_KG_PER_KM')
       <= l_truck_trips * get_setting('TRUCK_CO2_KG_PER_KM') then
      l_vehicle    := 'PICKUP';
      l_trips      := l_pickup_trips;
      l_co2_per_km := get_setting('PICKUP_CO2_KG_PER_KM');
    else
      l_vehicle    := 'TRUCK';
      l_trips      := l_truck_trips;
      l_co2_per_km := get_setting('TRUCK_CO2_KG_PER_KM');
    end if;

    -- Pooling only pays when the shared tour is shorter than direct trips
    if l_tour_km * l_trips >= l_individual_km then
      l_vehicle    := 'DIRECT';
      l_trips      := l_direct_trips;
      l_tour_km    := l_individual_km / l_trips;
      l_co2_per_km := get_setting('PICKUP_CO2_KG_PER_KM');
      l_sequence   := 'Direct delivery: ' || l_sequence;
    end if;
    l_stop_count := l_stops.count;

    insert into hl_routes (
      demand_id, total_qty_kg, stops, vehicle_type, trips,
      aggregated_km, individual_km, aggregated_co2_kg, individual_co2_kg,
      route_sequence
    ) values (
      p_demand_id, l_total_kg, l_stop_count, l_vehicle, l_trips,
      round(l_tour_km * l_trips, 2),
      round(l_individual_km, 2),
      round(l_tour_km * l_trips * l_co2_per_km, 2),
      round(l_individual_km * get_setting('PICKUP_CO2_KG_PER_KM'), 2),
      l_sequence
    );
  end plan_route;

  procedure run_matching (p_demand_id in number) is
    l_demand     hl_demands%rowtype;
    l_dest_lat   number;
    l_dest_lon   number;
    l_shelf_life number;
    l_buyer_ok   varchar2(10);
    l_remaining  number;
    l_alloc      number;
    l_w_qty      number := get_setting('WEIGHT_QUANTITY');
    l_w_grade    number := get_setting('WEIGHT_GRADE');
    l_w_timing   number := get_setting('WEIGHT_TIMING');
    l_w_dist     number := get_setting('WEIGHT_DISTANCE');
  begin
    select * into l_demand
      from hl_demands
     where demand_id = p_demand_id
       for update;

    if l_demand.status in ('CLOSED', 'CANCELLED') then
      raise_application_error(-20101, 'Demand ' || p_demand_id || ' is ' || l_demand.status);
    end if;

    select nvl(l_demand.delivery_lat, b.latitude), nvl(l_demand.delivery_lon, b.longitude)
      into l_dest_lat, l_dest_lon
      from hl_buyers b
     where b.buyer_id = l_demand.buyer_id;

    select shelf_life_days into l_shelf_life
      from hl_crops
     where crop_id = l_demand.crop_id;

    -- Re-running replaces proposals; accepted/delivered matches are kept
    delete from hl_matches
     where demand_id = p_demand_id
       and status = 'PROPOSED';

    select l_demand.quantity_kg - nvl(sum(allocated_kg), 0)
      into l_remaining
      from hl_matches
     where demand_id = p_demand_id
       and status in ('ACCEPTED', 'DELIVERED');

    if l_remaining > 0 then
      for c in (
        select s.*,
               round(l_w_qty * s.s_qty + l_w_grade * s.s_grade
                   + l_w_timing * s.s_timing + l_w_dist * s.s_dist, 4) as s_total
          from (
                select x.*,
                       round(least(x.avail, l_remaining) / l_remaining, 4) as s_qty,
                       hl_match_pkg.grade_score(x.grade, l_demand.grade_required) as s_grade,
                       hl_match_pkg.timing_score(x.harvest_from, x.harvest_to,
                                                 l_demand.need_by_date, l_shelf_life) as s_timing,
                       hl_match_pkg.distance_score(x.dist) as s_dist
                  from (
                        select h.harvest_id, h.grade, h.harvest_from, h.harvest_to,
                               f.full_name, f.location_name,
                               hl_match_pkg.available_kg(h.harvest_id) as avail,
                               hl_match_pkg.distance_km(f.latitude, f.longitude,
                                                        l_dest_lat, l_dest_lon) as dist
                          from hl_harvests h
                          join hl_farmers f on f.farmer_id = h.farmer_id
                         where h.crop_id = l_demand.crop_id
                           and h.status in ('OPEN', 'PARTIAL', 'COMMITTED')
                           and h.grade <= l_demand.grade_required
                           and not exists (
                                 select 1 from hl_matches m
                                  where m.demand_id = p_demand_id
                                    and m.harvest_id = h.harvest_id)
                       ) x
                 where x.avail > 0
               ) s
         where s.s_grade is not null
           and s.s_timing is not null
           and s.s_dist is not null
         order by s_total desc, s.dist
      ) loop
        exit when l_remaining <= 0;
        l_alloc := least(c.avail, l_remaining);

        insert into hl_matches (
          demand_id, harvest_id, allocated_kg, distance_km,
          score_total, score_quantity, score_grade, score_timing, score_distance,
          match_reason
        ) values (
          p_demand_id, c.harvest_id, l_alloc, c.dist,
          c.s_total, c.s_qty, c.s_grade, c.s_timing, c.s_dist,
          'Grade ' || c.grade
            || case when c.grade = l_demand.grade_required then ' (exact match)'
                    else ' (exceeds grade ' || l_demand.grade_required || ')' end
            || '; harvest ' || to_char(c.harvest_from, 'DD-Mon') || ' to '
            || to_char(c.harvest_to, 'DD-Mon')
            || case when c.harvest_to = l_demand.need_by_date
                    then ', ready on need-by date'
                    when c.harvest_to < l_demand.need_by_date
                    then ', ' || (l_demand.need_by_date - c.harvest_to) || ' day(s) before need-by date'
                    else ', overlaps need-by date' end
            || '; ' || round(c.dist) || ' km from delivery point'
            || '; supplies ' || l_alloc || ' of ' || l_demand.quantity_kg || ' kg'
        );

        l_remaining := l_remaining - l_alloc;
      end loop;
    end if;

    plan_route(p_demand_id);
    refresh_statuses(p_demand_id);
  end run_matching;

  procedure run_all_open is
  begin
    -- Earliest deadlines get first pick of supply
    for d in (select demand_id from hl_demands
               where status in ('OPEN', 'PARTIAL')
               order by need_by_date, created_at) loop
      run_matching(d.demand_id);
    end loop;
  end run_all_open;

  procedure rematch_all is
  begin
    delete from hl_matches
     where status = 'PROPOSED'
       and demand_id in (select demand_id from hl_demands
                          where status in ('OPEN', 'PARTIAL', 'FILLED'));

    for d in (select demand_id from hl_demands
               where status in ('OPEN', 'PARTIAL', 'FILLED')
               order by need_by_date, created_at) loop
      run_matching(d.demand_id);
    end loop;
  end rematch_all;

  procedure accept_match (p_match_id in number) is
  begin
    update hl_matches set status = 'ACCEPTED'
     where match_id = p_match_id and status = 'PROPOSED';
  end accept_match;

  procedure reject_match (p_match_id in number) is
    l_demand_id number;
  begin
    update hl_matches set status = 'REJECTED'
     where match_id = p_match_id and status in ('PROPOSED', 'ACCEPTED')
     returning demand_id into l_demand_id;
    if l_demand_id is not null then
      plan_route(l_demand_id);
      refresh_statuses(l_demand_id);
    end if;
  end reject_match;

  procedure run (p_demand_id in number) is
  begin
    run_matching(p_demand_id);
  end run;

  procedure confirm (p_match_id in number) is
    l_demand_id hl_matches.demand_id%type;
  begin
    update hl_matches set status = 'ACCEPTED'
     where match_id = p_match_id and status = 'PROPOSED'
     returning demand_id into l_demand_id;
    if l_demand_id is null then
      raise_application_error(-20111, 'Match ' || p_match_id || ' is not awaiting a farmer answer');
    end if;
    refresh_statuses(l_demand_id);
  end confirm;

  procedure decline (p_match_id in number) is
    l_demand_id hl_matches.demand_id%type;
  begin
    select demand_id into l_demand_id
      from hl_matches
     where match_id = p_match_id and status in ('PROPOSED', 'ACCEPTED');
    reject_match(p_match_id);
    run_matching(l_demand_id);
  exception
    when no_data_found then
      raise_application_error(-20112, 'Match ' || p_match_id || ' cannot be declined');
  end decline;

  procedure rerun_open is
  begin
    rematch_all;
  end rerun_open;

end hl_match_pkg;
/
