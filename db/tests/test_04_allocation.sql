-- Grade allocation never double-counts a lot
declare
  l_h number; l_school number; l_proc number; l_id number; l_n number;
begin
  select h.harvest_id into l_h from hl_harvests h join hl_farmers f on f.farmer_id = h.farmer_id
   where f.full_name = 'Wanjiru Muthoni' and h.grade = 'B';
  select buyer_id into l_school from hl_buyers where buyer_type = 'SCHOOL';
  select buyer_id into l_proc from hl_buyers where buyer_type = 'PROCESSOR';
  l_id := hl_alloc_pkg.allocate(l_h, l_school, 150);
  hlt.eq(hl_match_pkg.available_kg(l_h), 70, 'allocation reduces available kg');
  hlt.raises('declare n number; begin n := hl_alloc_pkg.allocate(' || l_h || ', ' || l_school || ', 100); end;', -20401, 'over-allocation refused');
  hlt.raises('declare n number; begin n := hl_alloc_pkg.allocate(' || l_h || ', ' || l_school || ', 0); end;', -20403, 'zero kg refused');
  select h.harvest_id into l_n from hl_harvests h join hl_farmers f on f.farmer_id = h.farmer_id
   where f.full_name = 'Wanjiru Muthoni' and h.grade = 'C' and h.status = 'OPEN';
  hlt.raises('declare n number; begin n := hl_alloc_pkg.allocate(' || l_n || ', ' || l_school || ', 10); end;', -20402, 'outlet must take the grade');
  select sum(kg) into l_n from hl_grade_allocation_v where crop_name = 'Roma tomatoes' and grade = 'B';
  hlt.eq(l_n, 640, 'grade split still adds up after allocating');
  hl_alloc_pkg.remove(l_id);
  hlt.eq(hl_match_pkg.available_kg(l_h), 220, 'remove gives the kg back');
  rollback;
end;
/
