-- HarvestLink: remove all objects (use before a clean re-install).
-- Triggers are dropped with their tables.
begin
  execute immediate 'drop package hl_apex_error';   -- only exists where APEX is installed
exception
  when others then
    if sqlcode != -4043 then raise; end if;
end;
/
drop package hl_ai;
drop table hl_ai_explanations purge;
drop view hl_my_data_v;
drop package hl_farmer_api;
drop table hl_erasures purge;
drop view hl_ledger_purge_v;
drop table hl_ledger_purges purge;
drop view hl_route_line_v;
drop view hl_route_stop_v;
drop view hl_grade_allocation_v;
drop view hl_allocations_v;
drop package hl_alloc_pkg;
drop view hl_my_offers_v;
drop view hl_my_harvests_v;
drop view hl_my_demands_v;
drop package hl_auth;
drop table hl_app_users purge;
drop package hl_demo;
drop view hl_impact_metrics_v;
drop view hl_near_miss_v;
drop view hl_fulfil_v;
drop view hl_match_v;
drop package hl_harvest_api;
drop package hl_demand_api;
drop view hl_agreements_v;
drop table hl_agreements purge;
drop view hl_impact_v;
drop view hl_grade_routing_v;
drop view hl_match_detail_v;
drop view hl_demand_summary_v;
drop view hl_harvest_availability_v;
drop package hl_match_pkg;
drop table hl_route_stops purge;
drop table hl_allocations purge;
drop table hl_matches purge;
drop table hl_routes purge;
drop table hl_demands purge;
drop table hl_harvests purge;
drop table hl_buyers purge;
drop table hl_farmers purge;
drop table hl_consent_texts purge;
drop table hl_crops purge;
drop table hl_settings purge;
