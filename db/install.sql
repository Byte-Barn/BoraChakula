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
show errors package body hl_match_pkg
