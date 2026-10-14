# HarvestLink database

Oracle Autonomous Database / Oracle Database 23ai schema, matching engine and demo data for HarvestLink.

## Files

| File | Contents |
|---|---|
| `01_schema.sql` | Tables: settings, crops, farmers, buyers, harvests, demands, matches, routes |
| `02_match_pkg.sql` | `HL_MATCH_PKG`: scoring, aggregation, route planning, status updates |
| `03_views.sql` | Views for APEX pages, maps and the impact dashboard |
| `04_seed.sql` | Reference data: matching settings and crops |
| `05_auto_match.sql` | Triggers that re-run matching after any change to demands, harvests or farm locations |
| `06_agreements.sql` | `HL_AGREEMENTS` blockchain table: tamper-evident ledger of confirmed, rejected and delivered farmer agreements |
| `07_api.sql` | Frontend contract: `HL_DEMAND_API`, `HL_HARVEST_API` and the `HL_MATCH_V`, `HL_FULFIL_V`, `HL_IMPACT_METRICS_V` views (see `docs/backend-api.md`) |
| `08_demo.sql` | `HL_DEMO`: the canvas demo story (Kijani Fresh Grocers, Kirinyaga farms), `seed`, `reset`, `featured_demand_id` |
| `09_auth.sql` | `HL_APP_USERS` and `HL_AUTH`: roles (buyer, farmer, ops), the signed-in party, and `HL_MY_*` views |
| `install.sql` / `uninstall.sql` | Install everything / drop everything |

## Install

**APEX (OCI Autonomous Database):** SQL Workshop → SQL Scripts → upload and run `01` to `05` in order.

**Whole stack (OCI):** `terraform apply` in `infra/` provisions the database and runs the scripts below; see `infra/README.md`.

**Scripted (OCI):** `python scripts/bootstrap_db.py --wallet infra/.wallet/wallet.zip` creates the schema user, APEX workspace and logins and installs everything (`--reset` reinstalls).

**SQLcl / SQL\*Plus:** from this directory run `@install.sql`.

**Local testing with Docker:**

```bash
docker run -d --name harvestlink-oracle -p 127.0.0.1:1521:1521 \
  -e ORACLE_PASSWORD=<pw> -e APP_USER=harvestlink -e APP_USER_PASSWORD=<pw> \
  gvenzl/oracle-free:23-slim-faststart
docker cp . harvestlink-oracle:/tmp/db
docker exec -w /tmp/db harvestlink-oracle sqlplus harvestlink/<pw>@localhost/FREEPDB1 @install.sql
```

## How matching works

`hl_match_pkg.run_matching(demand_id)` scores every eligible harvest from 0 to 1 on four equally weighted factors (weights are in `hl_settings`):

| Factor | Rule |
|---|---|
| Quantity | Share of the remaining order this farmer can fill (fewer stops preferred) |
| Grade | Exact grade = 1.0, one grade better = 0.7, two better = 0.5, worse = not eligible |
| Timing | Must start harvesting by the need-by date and still be fresh (crop shelf life); closer to need-by scores higher |
| Distance | Linear decay to `MAX_DISTANCE_KM` (road km estimated as straight-line × `ROAD_FACTOR`) |

The best-scoring farmers are allocated volume until the order is filled. Each match stores its scores and a plain-language reason.

`plan_route` then builds one nearest-neighbour pickup tour from the buyer through all matched farms. It compares truck vs pickup fleets and uses the one that emits less. If pooling would not beat farmers delivering directly, it falls back to `DIRECT`. Savings are measured against every farmer hiring their own pickup.

Frontend entry points (see `docs/backend-api.md`): `run`, `confirm`, `decline`, `rerun_open`. Other entry points: `rematch_all` (clears proposals and re-matches all active demands, earliest deadline first; called by the triggers), `run_all_open`, `accept_match`, `reject_match`.

Deleting a demand or harvest cascades to its matches and routes.

## Agreement ledger (blockchain table)

When a match becomes `ACCEPTED`, `DELIVERED`, or `REJECTED` after confirmation, a trigger appends the
agreed terms (farmer, buyer, crop, grade, kg, price, value, who recorded it) to `HL_AGREEMENTS`.
It is an Oracle blockchain table: rows cannot be updated, cannot be deleted for 16 days, and each
row's SHA2-512 hash is chained to the previous one. `HL_AGREEMENTS_V` exposes the chain position and
hash. Verify the chain with:

```sql
declare n number;
begin
  dbms_blockchain_table.verify_rows(user, 'HL_AGREEMENTS', number_of_rows_verified => n);
  dbms_output.put_line(n || ' rows verified');
end;
```

## Views for APEX

| View | Use |
|---|---|
| `hl_demand_summary_v` | Buyer demand list with fill %, farmers matched, km and CO₂ saved |
| `hl_match_detail_v` | Match list and APEX Map (farmer + delivery coordinates, stop order, reasons) |
| `hl_harvest_availability_v` | Farmer supply with remaining unallocated kg |
| `hl_grade_routing_v` | Unallocated produce with recommended channel and suggested buyer per grade |
| `hl_impact_v` | Dashboard totals: kg matched, loss avoided, km and CO₂ saved, farmer income uplift |

## Calibrate after market interviews

Update these with real figures before the pitch:

- `hl_crops`: `typical_broker_price_kg`, `typical_market_price_kg`, `shelf_life_days`
- `hl_settings`: `BASELINE_LOSS_RATE`, vehicle capacities and emission factors

Then re-run `begin hl_match_pkg.rematch_all; commit; end;`.
