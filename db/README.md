# HarvestLink database

Oracle Autonomous Database / Oracle Database 23ai schema, matching engine and demo data for HarvestLink.

## Files

| File | Contents |
|---|---|
| `01_schema.sql` | Tables: settings, crops, farmers, buyers, harvests, demands, matches, routes |
| `02_match_pkg.sql` | `HL_MATCH_PKG`: scoring, aggregation, route planning, status updates |
| `03_views.sql` | Views for APEX pages, maps and the impact dashboard |
| `04_seed.sql` | Demo data (fictional farmers and buyers in Murang'a, Kiambu, Nairobi); runs matching |
| `install.sql` / `uninstall.sql` | Install everything / drop everything |

## Install

**APEX (OCI Autonomous Database):** SQL Workshop → SQL Scripts → upload and run `01` to `04` in order.

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

Other entry points: `run_all_open` (earliest deadline first), `accept_match`, `reject_match` (re-plans the route; re-running matching fills the gap from other farmers).

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

Then re-run `begin hl_match_pkg.run_all_open; commit; end;`.
