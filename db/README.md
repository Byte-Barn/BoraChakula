# HarvestLink database

Oracle Autonomous Database / Oracle Database 23ai schema, matching engine and demo data for HarvestLink.

## Files

| File | Contents |
|---|---|
| `01_schema.sql` | Tables: settings, crops, consent notices, farmers, buyers, harvests, demands, matches, routes, route stops, allocations |
| `02_match_pkg.sql` | `HL_MATCH_PKG`: scoring, aggregation, route planning, status updates |
| `03_views.sql` | Views for APEX pages, maps and the impact dashboard |
| `04_seed.sql` | Reference data: matching settings and crops |
| `05_auto_match.sql` | Triggers that re-run matching after any change to demands, harvests or farm locations |
| `06_agreements.sql` | `HL_AGREEMENTS` blockchain table: tamper-evident ledger of confirmed, rejected and delivered farmer agreements |
| `07_api.sql` | Frontend contract: `HL_DEMAND_API`, `HL_HARVEST_API` and the `HL_MATCH_V`, `HL_FULFIL_V`, `HL_IMPACT_METRICS_V` views (see `docs/backend-api.md`) |
| `08_demo.sql` | `HL_DEMO`: the canvas demo story (Kijani Fresh Grocers, Kirinyaga farms), `seed`, `reset`, `featured_demand_id` |
| `09_auth.sql` | `HL_APP_USERS` and `HL_AUTH`: roles (buyer, farmer, ops), the signed-in party, and `HL_MY_*` views |
| `10_alloc.sql` | `HL_ALLOC_PKG` (allocate / remove with a no-double-counting guard) and `HL_ALLOCATIONS_V`, `HL_GRADE_ALLOCATION_V` |
| `11_routes.sql` | `HL_ROUTE_STOP_V` (pins, stop table, separate-trip lines) and `HL_ROUTE_LINE_V` (GeoJSON route line and totals) |
| `12_apex_error.sql` | `HL_APEX_ERROR.HANDLE`: the APEX error handling function (APEX databases only; skipped elsewhere) |
| `13_farmer_api.sql` | `HL_FARMER_API` (consent, data export, account deletion, ledger purge), `HL_ERASURES`, `HL_LEDGER_PURGES`, `HL_LEDGER_PURGE_V`, `HL_MY_DATA_V` (operations steps: `docs/operations.md`) |
| `14_ai.sql` | `HL_AI`: one-sentence match explanations in English or Kiswahili with Select AI, rule-based fallback; `HL_AI_EXPLANATIONS` cache; `AI_ENABLED` setting (off) |
| `tests/` | `run.sh` and the backend tests (see below) |
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

## Tests

```bash
db/tests/run.sh                                   # starts or reuses the hl-test-oracle container
HL_TEST_CONTAINER=harvestlink-oracle db/tests/run.sh   # reuse an existing Oracle Free container
```

The script installs everything into a throwaway user, runs each `tests/test_*.sql` (assertions use the `hlt`
helper in `tests/assert.sql`: `hlt.ok`, `hlt.eq`, `hlt.raises`), checks that `uninstall.sql` removes every
object, and exits non-zero on any failure. GitHub Actions runs it on pull requests that touch `db/`.

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

## Account emails with Brevo (optional)

Sign-up, verification, password reset and buyer approval emails (`HL_MAIL`, `db/15_accounts.sql`) wait in
`HL_MAIL_OUTBOX` until email is switched on. Switch it on with a Brevo API key and a sender address verified in
Brevo:

```bash
export HL_BREVO_API_KEY=<key> HL_MAIL_SENDER_EMAIL=<verified sender>   # optional: HL_MAIL_SENDER_NAME, HL_APP_URL
python scripts/enable_brevo.py --wallet infra/.wallet/wallet.zip --test-to <your email>
```

The script opens HTTPS to `api.brevo.com` (as ADMIN), stores the key as the APEX web credential `BREVO_API`,
sets the sender and the verify, reset and sign-in links, switches `MAIL_ENABLED` on, sends anything queued and,
with `--test-to`, sends a test email. `--disable` switches email off again. The credential and the settings
survive backend deploys.

## Select AI match sentences (optional)

`hl_ai.explain_match(match_id, 'en' | 'sw')` rewords a match's four reasons as one sentence with Select AI
(`DBMS_CLOUD_AI`, Autonomous Database only). It is off after install (`AI_ENABLED = 0`); until it is switched on,
or whenever the provider fails, it returns the reasons joined into one sentence, so pages never depend on AI.

Switch it on with an API key from a supported provider (`openai`, `cohere`, `anthropic`, `google`). The key is
read from the environment and stored only in the database, as credential `HL_AI_CRED`:

```bash
export HL_AI_PROVIDER=openai HL_AI_API_KEY=<key>   # optional: HL_AI_MODEL=<model name>
python scripts/enable_select_ai.py --wallet infra/.wallet/wallet.zip
```

The script grants `HARVESTLINK` `EXECUTE` on `DBMS_CLOUD` and `DBMS_CLOUD_AI` and opens the network ACL to the
provider's host (as ADMIN), then creates the credential and the `HL_EXPLAIN` profile, switches AI on and prints
the featured match's sentence in both languages. `--disable` switches it off again. For OCI Generative AI, create
an OCI credential and call `hl_ai.create_profile('oci', '<credential>', '<model>')` by hand.

A reinstall keeps the credential and profile. `bootstrap_db.py --reset` also keeps `AI_ENABLED`: when AI was on
and both still exist, it switches AI back on after reinstalling, so backend deploys no longer turn it off. A plain
install of `db/install.sql` still starts at 0; `begin hl_ai.set_enabled(true); commit; end;` switches it on. If
the schema user itself is recreated, rerun the script.

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

- `hl_crops`: `typical_broker_price_kg` (FAOSTAT 2024 farm-gate for six crops; FAO has no Kenyan price for French
  beans or kale, so those are estimates), `typical_market_price_kg` (estimates), `shelf_life_days` (estimates)
- `hl_settings`: vehicle capacities. `BASELINE_LOSS_RATE` (IFPRI 2022) and the emission factors (Kenyan fleet
  averages, GIZ/INFRAS 2018) are sourced; the `db/04_seed.sql` header lists the references. When you replace a figure, cite its source in the
  setting description and set the metric's `provenance` in `HL_IMPACT_METRICS_V` to `sourced`.

Then re-run `begin hl_match_pkg.rematch_all; commit; end;`.
