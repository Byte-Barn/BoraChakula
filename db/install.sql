-- HarvestLink: install schema, engine, views and demo data.
-- Run from SQL*Plus / SQLcl in this directory:  @install.sql
-- In APEX: SQL Workshop > SQL Scripts, upload and run each file in order.
whenever sqlerror exit failure rollback
set define off
@01_schema.sql
@02_match_pkg.sql
@03_views.sql
@04_seed.sql
@05_auto_match.sql
@06_agreements.sql
@07_api.sql
@08_demo.sql
@09_auth.sql
@10_alloc.sql
@11_routes.sql
@13_farmer_api.sql
@14_ai.sql
-- APEX environments only (needs APEX_ERROR): @12_apex_error.sql
-- The seed's ALTER TABLE statements leave dependent views needing recompilation
exec dbms_utility.compile_schema(schema => user, compile_all => false)
show errors package body hl_match_pkg
show errors package body hl_demand_api
show errors package body hl_harvest_api
show errors package body hl_farmer_api
show errors package body hl_ai
