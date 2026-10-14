-- HarvestLink: grade allocation.
--
-- Operations split each grade of a harvest across outlets: Grade A usually
-- goes to the demand buyer through matching, Grade B to markets and schools,
-- Grade C to processors. HL_ALLOC_PKG records those splits and guarantees the
-- same kilograms are never sent twice: matched + allocated kg on a harvest
-- can never exceed its expected kg, even with two operators at once.
--
-- Error codes: -20401..-20499 (docs/backend-api.md).

create or replace package hl_alloc_pkg as

  -- Sends p_kg of a harvest to a buyer (outlet). Locks the harvest row, so a
  -- concurrent allocation waits and then sees this one. Returns ALLOCATION_ID.
  function allocate (
    p_harvest_id in number,
    p_buyer_id   in number,
    p_kg         in number
  ) return number;

  -- Takes an allocation back; the kilograms become available to matching
  -- and other outlets again
  procedure remove (p_allocation_id in number);

end hl_alloc_pkg;
/

create or replace package body hl_alloc_pkg as

  function allocate (
    p_harvest_id in number,
    p_buyer_id   in number,
    p_kg         in number
  ) return number is
    l_grade     hl_harvests.grade%type;
    l_accepts   hl_buyers.accepted_grades%type;
    l_available number;
    l_id        hl_allocations.allocation_id%type;
  begin
    if p_kg is null or p_kg <= 0 then
      raise_application_error(-20403, 'Quantity must be more than 0 kg');
    end if;

    begin
      select grade into l_grade
        from hl_harvests
       where harvest_id = p_harvest_id
         for update;                      -- serialises allocations per harvest
    exception
      when no_data_found then
        raise_application_error(-20404, 'Harvest ' || p_harvest_id || ' does not exist');
    end;

    begin
      select accepted_grades into l_accepts from hl_buyers where buyer_id = p_buyer_id;
    exception
      when no_data_found then
        raise_application_error(-20405, 'Outlet ' || p_buyer_id || ' does not exist');
    end;
    if instr(',' || l_accepts || ',', ',' || l_grade || ',') = 0 then
      raise_application_error(-20402, 'This outlet does not take Grade ' || l_grade
                                      || ' (it takes ' || replace(l_accepts, ',', ', ') || ')');
    end if;

    l_available := hl_match_pkg.available_kg(p_harvest_id);
    if p_kg > l_available then
      raise_application_error(-20401, 'Only ' || l_available || ' kg of this Grade ' || l_grade
                                      || ' lot is left to allocate');
    end if;

    insert into hl_allocations (harvest_id, buyer_id, alloc_kg, created_by)
    values (p_harvest_id, p_buyer_id, p_kg, hl_auth.app_user)
    returning allocation_id into l_id;
    return l_id;
  end allocate;

  procedure remove (p_allocation_id in number) is
  begin
    delete from hl_allocations where allocation_id = p_allocation_id;
    if sql%rowcount = 0 then
      raise_application_error(-20406, 'Allocation ' || p_allocation_id || ' does not exist');
    end if;
    -- Freed produce may now fill an open demand
    hl_match_pkg.rematch_all;
  end remove;

end hl_alloc_pkg;
/

-- Every allocation with its lot and outlet (outlet table on the grade
-- routing screen)
create or replace view hl_allocations_v as
select a.allocation_id,
       a.harvest_id,
       f.full_name                       as farmer_name,
       f.location_name || ', ' || f.county as farmer_location,
       c.crop_name,
       h.grade,
       a.buyer_id,
       b.buyer_name                      as outlet_name,
       b.buyer_type                      as outlet_type,
       a.alloc_kg,
       a.created_by,
       a.created_at
  from hl_allocations a
  join hl_harvests h on h.harvest_id = a.harvest_id
  join hl_farmers f on f.farmer_id = h.farmer_id
  join hl_crops c on c.crop_id = h.crop_id
  join hl_buyers b on b.buyer_id = a.buyer_id;

-- How each crop's grade is split: kg matched to demand buyers, kg allocated
-- to outlets, and kg still unallocated (GradeAllocation component). One row
-- per crop, grade and destination; shares add up to 100% per crop and grade.
-- Only harvests still in play (not harvested or cancelled) are counted.
create or replace view hl_grade_allocation_v as
with lots as (
  select h.harvest_id, h.crop_id, c.crop_name, h.grade, h.expected_qty_kg
    from hl_harvests h
    join hl_crops c on c.crop_id = h.crop_id
   where h.status in ('OPEN', 'PARTIAL', 'COMMITTED')
), parts as (
  select l.crop_id, l.crop_name, l.grade, 'MATCHED' as destination_type,
         b.buyer_id, b.buyer_name as destination, m.allocated_kg as kg
    from lots l
    join hl_matches m on m.harvest_id = l.harvest_id and m.status <> 'REJECTED'
    join hl_demands d on d.demand_id = m.demand_id
    join hl_buyers b on b.buyer_id = d.buyer_id
  union all
  select l.crop_id, l.crop_name, l.grade, 'ALLOCATED',
         b.buyer_id, b.buyer_name, a.alloc_kg
    from lots l
    join hl_allocations a on a.harvest_id = l.harvest_id
    join hl_buyers b on b.buyer_id = a.buyer_id
  union all
  select l.crop_id, l.crop_name, l.grade, 'UNALLOCATED',
         null, 'Unallocated', hl_match_pkg.available_kg(l.harvest_id)
    from lots l
)
select crop_id,
       crop_name,
       grade,
       destination_type,
       buyer_id,
       destination,
       sum(kg)                                                        as kg,
       sum(sum(kg)) over (partition by crop_id, grade)                as grade_total_kg,
       round(sum(kg) / nullif(sum(sum(kg)) over (partition by crop_id, grade), 0) * 100, 1)
                                                                      as share_pct
  from parts
 group by crop_id, crop_name, grade, destination_type, buyer_id, destination
having sum(kg) > 0;
