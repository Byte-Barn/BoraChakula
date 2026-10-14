-- HarvestLink: remove all objects (use before a clean re-install)
drop view hl_impact_v;
drop view hl_grade_routing_v;
drop view hl_match_detail_v;
drop view hl_demand_summary_v;
drop view hl_harvest_availability_v;
drop package hl_match_pkg;
drop table hl_matches purge;
drop table hl_routes purge;
drop table hl_demands purge;
drop table hl_harvests purge;
drop table hl_buyers purge;
drop table hl_farmers purge;
drop table hl_crops purge;
drop table hl_settings purge;
