-- HarvestLink: backend API for the frontend.
--
-- The contract the canvas screens are built against (docs/backend-api.md):
-- pages read the views below and change data only through these packages and
-- HL_MATCH_PKG.run / confirm / decline / rerun_open. Tables underneath may
-- change; these names, parameters and columns stay stable.
--
-- Error codes raised here: -20201..-20299 (see docs/backend-api.md).

-- =============================================================================
-- HL_DEMAND_API: buyers post, cancel and close demands
-- =============================================================================
create or replace package hl_demand_api as

  c_min_lead_days constant pls_integer := 7;      -- farmers need time to plan
  c_max_qty_kg    constant number      := 50000;  -- 50 t per demand

  -- Validates, stores kg only, and returns the new DEMAND_ID. Matching runs
  -- automatically (HL_DEMANDS trigger), so HL_MATCH_V is filled on return.
  function create_demand (
    p_buyer_id     in number,
    p_crop_id      in number,
    p_grade        in varchar2,
    p_quantity_kg  in number,
    p_price_per_kg in number,
    p_need_by_date in date,
    p_delivery_lat in number   default null,  -- default: buyer location
    p_delivery_lon in number   default null,
    p_notes        in varchar2 default null,
    p_receiving_window in varchar2 default null   -- '06-10' | '10-14' | '14-18'
  ) return number;

  -- Saves a demand as DRAFT (matching ignores it). Pass p_demand_id to update
  -- an existing draft. Only basic checks; the full rules run on publish.
  -- Returns the DEMAND_ID.
  function save_draft (
    p_demand_id    in number   default null,
    p_buyer_id     in number,
    p_crop_id      in number,
    p_grade        in varchar2,
    p_quantity_kg  in number,
    p_price_per_kg in number,
    p_need_by_date in date,
    p_delivery_lat in number   default null,
    p_delivery_lon in number   default null,
    p_notes        in varchar2 default null,
    p_receiving_window in varchar2 default null
  ) return number;

  -- Applies the create_demand rules to a draft, opens it and runs matching
  procedure publish (p_demand_id in number);

  -- Releases proposed farmers, records confirmed ones as REJECTED in the
  -- ledger, and re-matches the freed supply to other demands
  procedure cancel (p_demand_id in number);

  -- Closes a demand once confirmed and delivered kg cover the quantity;
  -- returns TRUE when it was closed
  function close_if_filled (p_demand_id in number) return boolean;

end hl_demand_api;
/

create or replace package body hl_demand_api as

  procedure check_window (p_receiving_window in varchar2) is
  begin
    if p_receiving_window is not null and p_receiving_window not in ('06-10', '10-14', '14-18') then
      raise_application_error(-20208, 'Receiving time must be 06:00–10:00, 10:00–14:00 or 14:00–18:00');
    end if;
  end check_window;

  -- The rules a demand must meet before farmers see it
  procedure check_demand (
    p_grade in varchar2, p_quantity_kg in number, p_price_per_kg in number,
    p_need_by_date in date, p_delivery_lat in number, p_delivery_lon in number,
    p_receiving_window in varchar2
  ) is
  begin
    if p_quantity_kg is null or p_quantity_kg <= 0 or p_quantity_kg > c_max_qty_kg then
      raise_application_error(-20201, 'Quantity must be more than 0 kg and at most '
                                      || c_max_qty_kg || ' kg');
    end if;
    if p_need_by_date is null or trunc(p_need_by_date) < trunc(sysdate) + c_min_lead_days then
      raise_application_error(-20202, 'Delivery date must be at least '
                                      || c_min_lead_days || ' days from today');
    end if;
    if p_grade is null or p_grade not in ('A', 'B', 'C') then
      raise_application_error(-20203, 'Grade must be A, B or C');
    end if;
    if p_price_per_kg is null or p_price_per_kg <= 0 then
      raise_application_error(-20204, 'Price must be more than KES 0/kg');
    end if;
    if (p_delivery_lat is null) <> (p_delivery_lon is null) then
      raise_application_error(-20205, 'Give both delivery latitude and longitude, or neither');
    end if;
    check_window(p_receiving_window);
  end check_demand;

  function create_demand (
    p_buyer_id     in number,
    p_crop_id      in number,
    p_grade        in varchar2,
    p_quantity_kg  in number,
    p_price_per_kg in number,
    p_need_by_date in date,
    p_delivery_lat in number   default null,
    p_delivery_lon in number   default null,
    p_notes        in varchar2 default null,
    p_receiving_window in varchar2 default null
  ) return number is
    l_id hl_demands.demand_id%type;
  begin
    check_demand(p_grade, p_quantity_kg, p_price_per_kg, p_need_by_date,
                 p_delivery_lat, p_delivery_lon, p_receiving_window);

    insert into hl_demands (
      buyer_id, crop_id, grade_required, quantity_kg, price_per_kg,
      need_by_date, delivery_lat, delivery_lon, notes, receiving_window)
    values (
      p_buyer_id, p_crop_id, p_grade, p_quantity_kg, p_price_per_kg,
      trunc(p_need_by_date), p_delivery_lat, p_delivery_lon, p_notes, p_receiving_window)
    returning demand_id into l_id;
    return l_id;
  end create_demand;

  function save_draft (
    p_demand_id    in number   default null,
    p_buyer_id     in number,
    p_crop_id      in number,
    p_grade        in varchar2,
    p_quantity_kg  in number,
    p_price_per_kg in number,
    p_need_by_date in date,
    p_delivery_lat in number   default null,
    p_delivery_lon in number   default null,
    p_notes        in varchar2 default null,
    p_receiving_window in varchar2 default null
  ) return number is
    l_id hl_demands.demand_id%type := p_demand_id;
  begin
    check_window(p_receiving_window);
    if l_id is null then
      insert into hl_demands (
        buyer_id, crop_id, grade_required, quantity_kg, price_per_kg,
        need_by_date, delivery_lat, delivery_lon, notes, receiving_window, status)
      values (
        p_buyer_id, p_crop_id, p_grade, p_quantity_kg, p_price_per_kg,
        trunc(p_need_by_date), p_delivery_lat, p_delivery_lon, p_notes, p_receiving_window, 'DRAFT')
      returning demand_id into l_id;
    else
      update hl_demands
         set buyer_id = p_buyer_id, crop_id = p_crop_id, grade_required = p_grade,
             quantity_kg = p_quantity_kg, price_per_kg = p_price_per_kg,
             need_by_date = trunc(p_need_by_date), delivery_lat = p_delivery_lat,
             delivery_lon = p_delivery_lon, notes = p_notes, receiving_window = p_receiving_window
       where demand_id = l_id and status = 'DRAFT';
      if sql%rowcount = 0 then
        raise_application_error(-20209, 'Demand ' || l_id || ' is not a draft');
      end if;
    end if;
    return l_id;
  end save_draft;

  procedure publish (p_demand_id in number) is
    l_d hl_demands%rowtype;
  begin
    select * into l_d from hl_demands where demand_id = p_demand_id for update;
    if l_d.status <> 'DRAFT' then
      raise_application_error(-20209, 'Demand ' || p_demand_id || ' is not a draft');
    end if;
    check_demand(l_d.grade_required, l_d.quantity_kg, l_d.price_per_kg, l_d.need_by_date,
                 l_d.delivery_lat, l_d.delivery_lon, l_d.receiving_window);
    update hl_demands set status = 'OPEN', created_at = systimestamp where demand_id = p_demand_id;
    -- Status changes do not fire the auto-match trigger, so match now
    hl_match_pkg.rematch_all;
  exception
    when no_data_found then
      raise_application_error(-20207, 'Demand ' || p_demand_id || ' does not exist');
  end publish;

  procedure cancel (p_demand_id in number) is
    l_status hl_demands.status%type;
  begin
    select status into l_status from hl_demands where demand_id = p_demand_id for update;
    if l_status in ('CLOSED', 'CANCELLED') then
      raise_application_error(-20206, 'Demand ' || p_demand_id || ' is already ' || l_status);
    end if;

    delete from hl_matches where demand_id = p_demand_id and status = 'PROPOSED';
    update hl_matches set status = 'REJECTED'
     where demand_id = p_demand_id and status = 'ACCEPTED';
    delete from hl_routes where demand_id = p_demand_id;
    update hl_demands set status = 'CANCELLED' where demand_id = p_demand_id;

    -- The freed supply may fill other demands
    hl_match_pkg.rematch_all;
  exception
    when no_data_found then
      raise_application_error(-20207, 'Demand ' || p_demand_id || ' does not exist');
  end cancel;

  function close_if_filled (p_demand_id in number) return boolean is
    l_qty      hl_demands.quantity_kg%type;
    l_secured  number;
  begin
    select d.quantity_kg,
           (select nvl(sum(m.allocated_kg), 0) from hl_matches m
             where m.demand_id = d.demand_id and m.status in ('ACCEPTED', 'DELIVERED'))
      into l_qty, l_secured
      from hl_demands d
     where d.demand_id = p_demand_id
       and d.status in ('OPEN', 'PARTIAL', 'FILLED');

    if l_secured < l_qty then
      return false;
    end if;
    delete from hl_matches where demand_id = p_demand_id and status = 'PROPOSED';
    update hl_demands set status = 'CLOSED' where demand_id = p_demand_id;
    return true;
  exception
    when no_data_found then
      return false;
  end close_if_filled;

end hl_demand_api;
/

-- =============================================================================
-- HL_HARVEST_API: farmers register and update expected harvests
-- =============================================================================
create or replace package hl_harvest_api as

  -- Validates and returns the new HARVEST_ID; matching re-runs automatically
  function register (
    p_farmer_id       in number,
    p_crop_id         in number,
    p_grade           in varchar2,
    p_expected_qty_kg in number,
    p_harvest_from    in date,
    p_harvest_to      in date,
    p_notes           in varchar2 default null
  ) return number;

  -- Allowed until a buyer match on this harvest has been confirmed
  procedure update_estimate (
    p_harvest_id      in number,
    p_expected_qty_kg in number,
    p_harvest_from    in date,
    p_harvest_to      in date
  );

end hl_harvest_api;
/

create or replace package body hl_harvest_api as

  procedure check_values (p_qty in number, p_from in date, p_to in date) is
  begin
    if p_qty is null or p_qty <= 0 then
      raise_application_error(-20211, 'Expected quantity must be more than 0 kg');
    end if;
    if p_from is null or p_to is null or trunc(p_to) < trunc(p_from) then
      raise_application_error(-20212, 'Harvest end must be on or after harvest start');
    end if;
    if trunc(p_from) < trunc(sysdate) then
      raise_application_error(-20213, 'Harvest start cannot be in the past');
    end if;
  end check_values;

  function register (
    p_farmer_id       in number,
    p_crop_id         in number,
    p_grade           in varchar2,
    p_expected_qty_kg in number,
    p_harvest_from    in date,
    p_harvest_to      in date,
    p_notes           in varchar2 default null
  ) return number is
    l_id hl_harvests.harvest_id%type;
  begin
    check_values(p_expected_qty_kg, p_harvest_from, p_harvest_to);
    if p_grade is null or p_grade not in ('A', 'B', 'C') then
      raise_application_error(-20214, 'Grade must be A, B or C');
    end if;

    insert into hl_harvests (farmer_id, crop_id, grade, expected_qty_kg,
                             harvest_from, harvest_to, notes)
    values (p_farmer_id, p_crop_id, p_grade, p_expected_qty_kg,
            trunc(p_harvest_from), trunc(p_harvest_to), p_notes)
    returning harvest_id into l_id;
    return l_id;
  end register;

  procedure update_estimate (
    p_harvest_id      in number,
    p_expected_qty_kg in number,
    p_harvest_from    in date,
    p_harvest_to      in date
  ) is
    l_confirmed number;
  begin
    check_values(p_expected_qty_kg, p_harvest_from, p_harvest_to);

    select count(*) into l_confirmed
      from hl_matches
     where harvest_id = p_harvest_id and status in ('ACCEPTED', 'DELIVERED');
    if l_confirmed > 0 then
      raise_application_error(-20215, 'This harvest is already promised to a buyer; '
                                      || 'decline the match before changing it');
    end if;

    update hl_harvests
       set expected_qty_kg = p_expected_qty_kg,
           harvest_from    = trunc(p_harvest_from),
           harvest_to      = trunc(p_harvest_to)
     where harvest_id = p_harvest_id;
    if sql%rowcount = 0 then
      raise_application_error(-20216, 'Harvest ' || p_harvest_id || ' does not exist');
    end if;
  end update_estimate;

end hl_harvest_api;
/

-- =============================================================================
-- Views the screens read
-- =============================================================================

-- One row per farmer offered to a demand, ranked, with one plain-language
-- reason (and an ok/warn state) for each matching criterion. Farmer phone
-- numbers stay masked until the farmer has confirmed.
create or replace view hl_match_v as
select m.match_id,
       m.demand_id,
       m.harvest_id,
       row_number() over (partition by m.demand_id
                          order by case when m.status = 'REJECTED' then 1 else 0 end,
                                   m.score_total desc, m.distance_km) as rank_no,
       case m.status
         when 'PROPOSED'  then 'PENDING'
         when 'ACCEPTED'  then 'MATCHED'
         when 'DELIVERED' then 'MATCHED'
         when 'REJECTED'  then 'DECLINED'
       end                                                   as ui_status,
       m.status                                              as match_status,
       f.farmer_id,
       f.full_name                                           as farmer_name,
       f.location_name || ', ' || f.county                   as farmer_location,
       -- Unmasked once the farmer has confirmed, and only for the buyer who
       -- owns the demand, the farmer, operations and scripts
       case when m.status in ('ACCEPTED', 'DELIVERED')
             and hl_match_pkg.can_act(m.demand_id, m.harvest_id) = 'Y' then f.phone
            else '•••• ••• ' || substr(f.phone, -3) end      as farmer_phone,
       f.latitude                                            as farmer_lat,
       f.longitude                                           as farmer_lon,
       c.crop_name,
       h.grade,
       d.grade_required,
       h.expected_qty_kg                                     as available_kg,
       m.allocated_kg,
       h.harvest_from,
       h.harvest_to,
       d.need_by_date,
       round(m.distance_km)                                  as distance_km,
       m.stop_order,
       m.score_total,
       -- Quantity
       'ok'                                                  as reason_qty_state,
       m.allocated_kg || ' kg of ' || h.expected_qty_kg || ' kg allocated, '
         || round(m.allocated_kg / d.quantity_kg * 100) || '% of the order'
                                                             as reason_qty,
       -- Grade
       'ok'                                                  as reason_grade_state,
       'Grade ' || h.grade
         || case when h.grade = d.grade_required then ' meets'
                 else ' exceeds' end
         || ' the Grade ' || d.grade_required || ' request'  as reason_grade,
       -- Harvest window
       case when m.score_timing >= 0.5 then 'ok' else 'warn' end
                                                             as reason_window_state,
       to_char(h.harvest_from, 'DD Mon') || '–' || to_char(h.harvest_to, 'DD Mon')
         || case when h.harvest_to < d.need_by_date
                 then ', ready before delivery on ' || to_char(d.need_by_date, 'Dy DD Mon')
                 when h.harvest_to = d.need_by_date
                 then ', ready on the delivery day'
                 else ', overlaps delivery on ' || to_char(d.need_by_date, 'Dy DD Mon') end
                                                             as reason_window,
       -- Distance
       -- Warn on the farthest farm of a multi-farm pickup (it stretches the route)
       case when m.status <> 'REJECTED'
             and count(case when m.status <> 'REJECTED' then 1 end)
                   over (partition by m.demand_id) > 1
             and m.distance_km = max(case when m.status <> 'REJECTED' then m.distance_km end)
                   over (partition by m.demand_id)
            then 'warn' else 'ok' end                       as reason_dist_state,
       round(m.distance_km) || ' km by road to the delivery point'
         || case when m.status <> 'REJECTED'
                  and count(case when m.status <> 'REJECTED' then 1 end)
                        over (partition by m.demand_id) > 1
                  and m.distance_km = max(case when m.status <> 'REJECTED' then m.distance_km end)
                        over (partition by m.demand_id)
                 then ', the farthest farm on this pickup' end
                                                             as reason_dist,
       (select a.row_hash_short
          from hl_agreements_v a
         where a.match_id = m.match_id
         order by a.chain_seq desc
         fetch first 1 row only)                             as agreement_hash
  from hl_matches m
  join hl_demands d on d.demand_id = m.demand_id
  join hl_harvests h on h.harvest_id = m.harvest_id
  join hl_farmers f on f.farmer_id = h.farmer_id
  join hl_crops c on c.crop_id = h.crop_id;

-- Farms that grow the crop but were not matched to an active demand, with the
-- criterion that ruled each out ("Not matched" card). Same reason columns as
-- HL_MATCH_V; a failing criterion has state 'no'.
create or replace view hl_near_miss_v as
with c as (
  select d.demand_id, d.need_by_date, d.grade_required, d.quantity_kg,
         h.harvest_id, h.grade, h.expected_qty_kg, h.harvest_from, h.harvest_to,
         f.farmer_id, f.full_name, f.location_name, f.county, f.latitude, f.longitude,
         cr.shelf_life_days,
         hl_match_pkg.distance_km(f.latitude, f.longitude,
                                  nvl(d.delivery_lat, b.latitude),
                                  nvl(d.delivery_lon, b.longitude)) as dist,
         hl_match_pkg.available_kg(h.harvest_id) as avail
    from hl_demands d
    join hl_buyers b on b.buyer_id = d.buyer_id
    join hl_crops cr on cr.crop_id = d.crop_id
    join hl_harvests h on h.crop_id = d.crop_id
                      and h.status in ('OPEN', 'PARTIAL', 'COMMITTED')
    join hl_farmers f on f.farmer_id = h.farmer_id
   where d.status in ('OPEN', 'PARTIAL', 'FILLED')
     and h.grade = d.grade_required
     and not exists (select 1 from hl_matches m
                      where m.demand_id = d.demand_id and m.harvest_id = h.harvest_id)
), r as (
  select c.*,
         case when avail <= 0 then 'no' else 'ok' end as qty_state,
         case when harvest_from > need_by_date
                or need_by_date - harvest_to > shelf_life_days then 'no' else 'ok' end as window_state,
         case when dist > hl_match_pkg.get_setting('MAX_DISTANCE_KM') then 'no' else 'ok' end as dist_state
    from c
)
select demand_id,
       harvest_id,
       farmer_id,
       full_name                                         as farmer_name,
       location_name || ', ' || county                   as farmer_location,
       latitude                                          as farmer_lat,
       longitude                                         as farmer_lon,
       grade,
       expected_qty_kg                                   as available_kg,
       harvest_from,
       harvest_to,
       round(dist)                                       as distance_km,
       qty_state                                         as reason_qty_state,
       case when qty_state = 'no' then 'All ' || expected_qty_kg || ' kg already promised to other buyers'
            else greatest(avail, 0) || ' kg available' end as reason_qty,
       'ok'                                              as reason_grade_state,
       'Grade ' || grade || ' meets the Grade ' || grade_required || ' request' as reason_grade,
       window_state                                      as reason_window_state,
       case when harvest_from > need_by_date
            then 'Harvest starts ' || to_char(harvest_from, 'Dy DD Mon')
                 || ', after delivery on ' || to_char(need_by_date, 'Dy DD Mon')
            when need_by_date - harvest_to > shelf_life_days
            then 'Harvest ends ' || to_char(harvest_to, 'Dy DD Mon') || ', too early to stay fresh'
            else to_char(harvest_from, 'DD Mon') || '–' || to_char(harvest_to, 'DD Mon') end
                                                         as reason_window,
       dist_state                                        as reason_dist_state,
       round(dist) || ' km by road to the delivery point'
         || case when dist_state = 'no' then ', beyond the matching radius' end as reason_dist
  from r
 where qty_state = 'no' or window_state = 'no' or dist_state = 'no';

-- Fulfilment per demand: matched (farmer confirmed), pending (awaiting the
-- farmer) and unmatched kg, as the FulfilmentBar draws them
create or replace view hl_fulfil_v as
select d.demand_id,
       d.buyer_id,
       b.buyer_name,
       d.crop_id,
       c.crop_name,
       d.grade_required,
       d.quantity_kg                                          as target_kg,
       nvl(x.matched_kg, 0)                                   as matched_kg,
       nvl(x.pending_kg, 0)                                   as pending_kg,
       greatest(d.quantity_kg - nvl(x.matched_kg, 0) - nvl(x.pending_kg, 0), 0)
                                                              as unmatched_kg,
       nvl(x.matched_farmers, 0)                              as matched_farmers,
       nvl(x.pending_farmers, 0)                              as pending_farmers,
       round(least(nvl(x.matched_kg, 0) + nvl(x.pending_kg, 0), d.quantity_kg)
             / d.quantity_kg * 100)                           as fill_pct,
       d.price_per_kg,
       d.quantity_kg * d.price_per_kg                         as order_value_kes,
       d.need_by_date,
       d.receiving_window,
       d.status
  from hl_demands d
  join hl_buyers b on b.buyer_id = d.buyer_id
  join hl_crops c on c.crop_id = d.crop_id
  left join (
        select demand_id,
               sum(case when status in ('ACCEPTED', 'DELIVERED') then allocated_kg end) as matched_kg,
               sum(case when status = 'PROPOSED' then allocated_kg end)                 as pending_kg,
               count(case when status in ('ACCEPTED', 'DELIVERED') then 1 end)          as matched_farmers,
               count(case when status = 'PROPOSED' then 1 end)                          as pending_farmers
          from hl_matches
         group by demand_id
       ) x on x.demand_id = d.demand_id;

-- One row per impact metric, with its unit, provenance and the method text
-- the StatCard's "How this is calculated" note shows.
--   provenance: live (computed from records), sourced (records x a published
--   factor, cited in the method), simulated (prototype stand-in), demo
--   (illustrative factor or seeded price). Sources: db/04_seed.sql header.
create or replace view hl_impact_metrics_v as
with i as (select * from hl_impact_v),
     r as (select nvl(sum(stops), 0) as separate_trips, nvl(sum(trips), 0) as shared_trips
             from hl_routes where vehicle_type <> 'DIRECT'),
     a as (select count(distinct match_id) as confirmed
             from hl_agreements where event = 'ACCEPTED')
select 1 as sort_order, 'MARKET_ACCESS' as metric_group, 'PRODUCE_SOURCED' as metric_key,
       'Produce sourced' as label, i.total_matched_kg as value, 'kg' as unit, 'live' as provenance,
       'Sum of kg allocated to farmers on proposed, confirmed and delivered matches.' as method
  from i
union all
select 2, 'MARKET_ACCESS', 'FARMERS_REACHED', 'Farmers reached', i.farmers_matched, 'farmers', 'live',
       'Distinct farmers with at least one allocation that was not declined.'
  from i
union all
select 3, 'MARKET_ACCESS', 'DEMANDS_SERVED', 'Demands served', i.demands_served, 'demands', 'live',
       'Distinct buyer demands with at least one farmer allocated.'
  from i
union all
select 4, 'MARKET_ACCESS', 'AGREEMENTS_RECORDED', 'Agreements recorded', a.confirmed, 'agreements', 'live',
       'Farmer confirmations written to the HL_AGREEMENTS blockchain table.'
  from a
union all
select 5, 'MARKET_ACCESS', 'INCOME_UPLIFT', 'Estimated farmer income uplift', i.farmer_income_uplift_kes, 'KES', 'demo',
       'Allocated kg × (buyer price − typical broker price). Grade C counts against KES 0, '
       || 'because it usually goes unsold. Broker prices are FAO farm-gate producer prices for Kenya '
       || '(FAOSTAT 2024, official values) for tomatoes, onions, green peppers, carrots, cabbage and '
       || 'avocado; FAO has no Kenyan price for French beans or kale, so those two are team estimates.'
  from i
union all
select 6, 'WASTE_EMISSIONS', 'LOSS_AVOIDED', 'Estimated post-harvest loss avoided', i.loss_avoided_kg, 'kg', 'sourced',
       'Allocated kg × baseline loss rate of '
       || to_char(hl_match_pkg.get_setting('BASELINE_LOSS_RATE') * 100, 'fm990') || '%: tomato losses from farm '
       || 'to point of sale without a pre-arranged buyer, 28.2% of value (IFPRI, Laikipia County, 2022).'
  from i
union all
select 7, 'WASTE_EMISSIONS', 'DISTANCE_SAVED', 'Truck distance saved', i.km_saved, 'km', 'simulated',
       'Each farmer travelling alone minus one shared pickup route. Distances are straight-line × '
       || to_char(hl_match_pkg.get_setting('ROAD_FACTOR'), 'fm990.0') || ' (simulated road distance).'
  from i
union all
select 8, 'WASTE_EMISSIONS', 'CO2_AVOIDED', 'Estimated CO₂ avoided', i.co2_saved_kg, 'kg CO₂', 'simulated',
       'Kilometres saved × Kenyan road fleet CO₂ factors (GIZ/INFRAS 2018, reference year 2015: light '
       || 'commercial vehicle ' || to_char(hl_match_pkg.get_setting('PICKUP_CO2_KG_PER_KM'), 'fm0.000')
       || ', heavy goods vehicle ' || to_char(hl_match_pkg.get_setting('TRUCK_CO2_KG_PER_KM'), 'fm0.000')
       || ' kg CO₂ per km). '
       || 'Factors are published; distances are simulated, so the total is too.'
  from i
union all
select 9, 'WASTE_EMISSIONS', 'TRIPS_REPLACED', 'Trips replaced', r.separate_trips - r.shared_trips, 'trips', 'simulated',
       'Separate farmer trips minus shared pickup trips, on demands where pooling beats direct delivery.'
  from r;
