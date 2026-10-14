-- Pickup stops agree with route totals
declare
  l_d number := hl_demo.featured_demand_id;
  l_r hl_routes%rowtype;
  l_legs number; l_n number; l_type varchar2(20);
begin
  select * into l_r from hl_routes where demand_id = l_d;
  select sum(leg_km), count(*) into l_legs, l_n from hl_route_stops where route_id = l_r.route_id;
  hlt.eq(l_n, l_r.stops + 1, 'one stop per farm plus the buyer');
  hlt.ok(abs(l_legs * l_r.trips - l_r.aggregated_km) < 0.05, 'legs x trips = aggregated km');
  select stop_type into l_type from hl_route_stops where route_id = l_r.route_id and stop_no = l_n;
  hlt.eq(l_type, 'DESTINATION', 'route ends at the buyer');
  select count(*) into l_n from hl_route_line_v where demand_id = l_d and route_geojson like '{"type":"LineString","coordinates":[[%]]}';
  hlt.eq(l_n, 1, 'GeoJSON line is built');
end;
/
