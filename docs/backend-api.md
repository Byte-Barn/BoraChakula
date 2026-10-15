# HarvestLink backend API for the frontend

This is the contract between the canvas screens (APEX pages) and the database.
**Pages read the views and change data only by calling the procedures below.**
Tables behind them may change; the names, parameters and columns here will not
change without a note in this file.

- Database: Oracle Autonomous AI Database 26ai, schema `HARVESTLINK` (APEX parsing schema).
- Source: `db/02_match_pkg.sql` (matching), `db/06_agreements.sql` (ledger), `db/07_api.sql` (APIs and contract views), `db/08_demo.sql` (demo dataset and reset), `db/09_auth.sql` (roles and "my" views), `db/10_alloc.sql` (grade allocation), `db/11_routes.sql` (route stops and map views), `db/13_farmer_api.sql` (farmer consent, data export and account deletion), `db/14_ai.sql` (Select AI match sentences).
- Status of each item: **Ready** (in this PR) or **Planned** (a later backend PR, listed at the end).

## Conventions

| Topic | Rule |
|---|---|
| Quantities | Always kilograms (`*_kg`). Show `t` in headlines by dividing by 1,000 in the page. |
| Money | Kenyan shillings (`*_kes`, `price_per_kg` is KES/kg). |
| Dates | Oracle `DATE` with no time. Format in the page: `Dy DD Mon` for UI, `DD Mon YYYY` for records. |
| IDs | Numbers. Display IDs such as `HL-D-0142` are built in the page: `'HL-D-' || lpad(demand_id, 4, '0')`. |
| Transactions | Procedures never commit. APEX commits at the end of the page process, so a failed step rolls the whole submit back. |
| Errors | `ORA-20xxx` with a message written for the end user. Show `sqlerrm` text after the code in an Alert (see the error table). |
| Automatic matching | Inserting, editing or deleting demands, harvests or farm locations re-runs matching inside the same transaction. After `create_demand` returns, `HL_MATCH_V` already has the ranked farmers. |

### Status vocabulary

| Where | Values | Show as |
|---|---|---|
| `HL_MATCH_V.UI_STATUS` | `PENDING` (awaiting farmer), `MATCHED` (farmer confirmed or delivered), `DECLINED` | StatusBadge `pending` / `matched` / `unmatched` |
| `HL_FULFIL_V.STATUS`, demands | `OPEN`, `PARTIAL`, `FILLED` (proposals cover it), `CLOSED`, `CANCELLED` | |
| `reason_*_state` | `ok`, `warn` (`HL_MATCH_V`), `no` (`HL_NEAR_MISS_V`) | MatchCard reason icon: check, warning, cross |
| `provenance` | `live`, `sourced` (records × a published factor, cited in `method`), `simulated`, `demo` | ProvenanceTag of the same name (`sourced` is new: give it its own style) |

## Roles and the signed-in party — Ready

Every APEX login maps to one role. Buyer and farmer logins are linked to their party by name, so they keep
working after `hl_demo.reset`.

| Login | Role | Party |
|---|---|---|
| `BUYER_DEMO` | `BUYER` | Kijani Fresh Grocers |
| `FARMER_DEMO` | `FARMER` | Wanjiru Muthoni |
| `OPS_DEMO`, `JUDGE`, the workspace developer | `OPS` | sees everything |

Passwords are in the team's secrets file (`HL_ROLE_DEMO_PASSWORD`, `HL_DEMO_PASSWORD`), never in the repo.

| Use | Call |
|---|---|
| Authorization scheme `IS_BUYER` (PL/SQL function returning boolean) | `return hl_auth.is_buyer;` |
| Authorization scheme `IS_FARMER` | `return hl_auth.is_farmer;` |
| Authorization scheme `IS_OPS` | `return hl_auth.is_ops;` |
| Pages operations may also open | `return hl_auth.is_buyer or hl_auth.is_ops;` |
| Application item `G_BUYER_ID` / `G_FARMER_ID` (computation after login) | `hl_auth.buyer_id` / `hl_auth.farmer_id` (null for other roles) |
| Current role, e.g. to choose the home page | `hl_auth.role` returns `BUYER`, `FARMER`, `OPS` or null |
| Map a new login (admin) | `hl_auth.register_user(p_user_name, p_role, p_party_name)` |

"My" views filter to the signed-in party, so pages need no ID parameter:

| View | Rows | Screen |
|---|---|---|
| `HL_MY_DEMANDS_V` | The buyer's demands; same columns as `HL_FULFIL_V` | Buyer dashboard |
| `HL_MY_HARVESTS_V` | The farmer's harvests: `crop_name`, `grade`, `expected_qty_kg`, `available_kg` (not yet promised), window, `status` | Farmer dashboard |
| `HL_MY_OFFERS_V` | Matches offered to the farmer with the buyer's terms: `ui_status`, `allocated_kg`, `price_per_kg`, `offer_value_kes`, `need_by_date`, `buyer_name`, `buyer_location`, reasons, `agreement_hash` | Farmer dashboard (accept: `hl_match_pkg.confirm`, decline: `hl_match_pkg.decline`) |

## Screen by screen

### 1 · Landing page (public) — Ready

| Needs | Source |
|---|---|
| Example-in-numbers strip | `HL_IMPACT_METRICS_V` rows `PRODUCE_SOURCED`, `FARMERS_REACHED`, `DISTANCE_SAVED`, `LOSS_AVOIDED` (`value`, `unit`, `provenance`) |
| Example demand card and fulfilment bar | `HL_FULFIL_V` where `demand_id = hl_demo.featured_demand_id` (`target_kg`, `matched_kg`, `pending_kg`, `unmatched_kg`) |

The page must be public (no login): read-only queries only, label figures "Illustrative figures from the demo dataset".

### 2 · Farmer: register harvest (phone) — Ready

```sql
-- Page process "Register harvest" (P20)
:P20_HARVEST_ID := hl_harvest_api.register(
  p_farmer_id       => hl_auth.farmer_id,   -- the signed-in farmer
  p_crop_id         => :P20_CROP_ID,
  p_grade           => :P20_GRADE,         -- 'A' | 'B' | 'C'
  p_expected_qty_kg => :P20_QTY_KG,        -- convert crates × 25 in the page if the unit picker says crates
  p_harvest_from    => :P20_FROM,
  p_harvest_to      => :P20_TO,
  p_notes           => :P20_NOTES);
```

To change an estimate: `hl_harvest_api.update_estimate(p_harvest_id, p_expected_qty_kg, p_harvest_from, p_harvest_to)`; refused (`-20215`) once a buyer match on it is confirmed.

"A buyer is already looking" hint: `select ... from hl_fulfil_v where crop_id = :P20_CROP_ID and status in ('OPEN','PARTIAL') and unmatched_kg > 0 order by need_by_date fetch first 1 row only`.

Crop tiles: `select crop_id, crop_name from hl_crops order by crop_name`.

### 3 · Buyer dashboard — Ready

| Needs | Source |
|---|---|
| Demands table | `HL_MY_DEMANDS_V` (`crop_name`, `grade_required`, `target_kg`, `matched_kg + pending_kg` as sourced, `need_by_date`, `status`) |
| Stat cards | `count(*)` active demands, `sum(matched_kg)` confirmed supply, `sum(pending_kg)` awaiting farmers, all from `HL_MY_DEMANDS_V` |
| "Farmers have not confirmed" alert | `HL_MATCH_V` where `ui_status = 'PENDING'` for the buyer's demands |
| Route preview | `HL_MATCH_V` (`farmer_lat`, `farmer_lon`, `stop_order`, `ui_status`) plus the demand's route (see 7) |

Operations users have no buyer of their own; give them a buyer select list and read `HL_FULFIL_V` instead.

### 4 · Post a demand — Ready

```sql
-- Page process "Post demand" (P11)
:P11_DEMAND_ID := hl_demand_api.create_demand(
  p_buyer_id     => hl_auth.buyer_id,     -- the signed-in buyer
  p_crop_id      => :P11_CROP_ID,
  p_grade        => :P11_GRADE,
  p_quantity_kg  => :P11_QTY_KG,          -- tonnes × 1000 in the page
  p_price_per_kg => :P11_PRICE_PER_KG,
  p_need_by_date => :P11_DELIVERY_DATE,   -- at least 7 days from today
  p_delivery_lat => :P11_LAT,             -- optional; buyer location when null
  p_delivery_lon => :P11_LON,
  p_notes        => :P11_NOTES,
  p_receiving_window => :P11_WINDOW);     -- '06-10' | '10-14' | '14-18', optional
-- then branch to the matching page with P12_DEMAND_ID = :P11_DEMAND_ID
```

Review panel values are computed in the page (`qty × price` = order value).

| Button | Call |
|---|---|
| Save draft | `:P11_DEMAND_ID := hl_demand_api.save_draft(p_demand_id => :P11_DEMAND_ID, ...same parameters...);` (first save: pass null; drafts skip the 7-day and 50 t rules and are never matched) |
| Post demand (from a draft) | `hl_demand_api.publish(p_demand_id => :P11_DEMAND_ID);` applies every rule above, opens the demand and matches it |

Drafts have `status = 'DRAFT'` in `HL_FULFIL_V` and `HL_MY_DEMANDS_V`. `receiving_window` is a column in both.

### 5 · Matching and aggregation — Ready

| Needs | Source |
|---|---|
| Header and fulfilment bar | `HL_FULFIL_V` where `demand_id = :P12_DEMAND_ID` |
| Ranked farmer cards | `HL_MATCH_V` where `demand_id = :P12_DEMAND_ID and ui_status <> 'DECLINED' order by rank_no` |
| "Not matched" card | `HL_NEAR_MISS_V` where `demand_id = :P12_DEMAND_ID`: farms that grow the crop but were ruled out, with the same four reason columns (a failing criterion has state `no`). Farmers who said no are in `HL_MATCH_V` with `ui_status = 'DECLINED'`. |
| Agreement recorded | `HL_MATCH_V.AGREEMENT_HASH` (16 hex digits) once confirmed |

`HL_MATCH_V` columns for MatchCard: `rank_no`, `ui_status`, `farmer_name`, `farmer_location`, `farmer_phone` (masked until confirmed), `distance_km`, `harvest_from`, `harvest_to`, `available_kg`, `allocated_kg`, `grade`, and four reasons, each a sentence plus a state:

| Reason | Text column | State column |
|---|---|---|
| Quantity | `reason_qty` | `reason_qty_state` |
| Grade | `reason_grade` | `reason_grade_state` |
| Harvest window | `reason_window` | `reason_window_state` |
| Distance | `reason_dist` | `reason_dist_state` |

Buttons:

| Button | Call |
|---|---|
| Confirm *n* kg for *farmer* | `hl_match_pkg.confirm(p_match_id => :MATCH_ID)` — writes the agreement to the blockchain ledger |
| Farmer declined | `hl_match_pkg.decline(p_match_id => :MATCH_ID)` — skips that farm for this demand and re-matches the gap |
| Run matching again | `hl_match_pkg.run(p_demand_id => :P12_DEMAND_ID)` |

**One-sentence explanation (Select AI, optional).** Show it above or beside the four reasons, never instead of them:

```sql
select m.*,
       hl_ai.explain_match(m.match_id, 'en') as why_sentence,   -- 'sw' for Kiswahili (farmer pages)
       hl_ai.explained_by(m.match_id, 'en')  as why_source      -- 'AI' or 'RULES'
  from hl_match_v m
 where m.demand_id = :P12_DEMAND_ID and m.ui_status <> 'DECLINED'
 order by m.rank_no
```

- With AI switched off (the default), not set up, or failing, `why_sentence` is the four reasons joined into one
  sentence and `why_source` is `RULES`, so the page works the same either way. Show a small "AI" tag only when
  `why_source = 'AI'`, or hide the sentence when it is `RULES` to avoid repeating the reasons.
- Sentences are stored per match and language and reused until the match's reasons change, so the provider is
  called once per card, not on every page view. After a failed call the session uses the rules for 5 minutes.
- The prompt holds only the reasons, crop, grade and status: never names or phone numbers.
- Switch on or off: `scripts/enable_select_ai.py` (see `db/README.md`), or `hl_ai.set_enabled(true | false)`.

### 6 · Grade routing — Ready

| Needs | Source |
|---|---|
| Grade explainer cards and split bars (GradeAllocation) | `HL_GRADE_ALLOCATION_V` where `crop_id = :CROP_ID`: one row per grade and destination, with `destination_type` `MATCHED` (sold to a demand buyer), `ALLOCATED` (sent to an outlet) or `UNALLOCATED`, plus `destination`, `kg`, `grade_total_kg` and `share_pct`. Shares add up to 100% per grade |
| Lots still to place, with a suggested outlet | `HL_GRADE_ROUTING_V`: `farmer_name`, `grade`, `available_kg`, `recommended_channel`, `suggested_buyer`, `suggested_buyer_type`, `suggested_buyer_km` |
| Outlet allocations table | `HL_ALLOCATIONS_V`: `allocation_id`, `farmer_name`, `crop_name`, `grade`, `outlet_name`, `outlet_type`, `alloc_kg`, `created_by`, `created_at` |
| Outlet picker for a lot | `select buyer_id, buyer_name from hl_buyers where instr(',' \|\| accepted_grades \|\| ',', ',' \|\| :GRADE \|\| ',') > 0` |

| Button | Call |
|---|---|
| Allocate *n* kg to an outlet | `:ID := hl_alloc_pkg.allocate(p_harvest_id => :HARVEST_ID, p_buyer_id => :BUYER_ID, p_kg => :KG);` |
| Remove an allocation | `hl_alloc_pkg.remove(p_allocation_id => :ALLOCATION_ID);` (freed kg are re-matched) |

The guard: matched + allocated kg on a harvest can never exceed its expected kg. `allocate` locks the harvest
row, so two operators allocating the same lot at once cannot double-count; the second waits, then gets `-20401`
if too little is left. Allocated kg are no longer offered to matching.

### 7 · Logistics and pickup route — Ready

Routes are planned automatically whenever matching runs. A demand gets a shared `TRUCK` or `PICKUP` trip when
pooling saves distance, otherwise `DIRECT` (each farmer delivers; no stops). All distances and times are
**simulated**: straight-line × `ROAD_FACTOR`, `AVG_SPEED_KMH` and `STOP_MINUTES` from `HL_SETTINGS`. The vehicle
leaves the buyer at `ROUTE_START_HOUR` the day before delivery.

| Needs | Source |
|---|---|
| Route summary (RouteSummary) | `HL_ROUTE_LINE_V` where `demand_id = :DEMAND_ID`: `vehicle_type`, `trips`, `stops`, `aggregated_km`, `individual_km`, `km_saved`, `co2_saved_kg`, `last_pickup_at`, `delivered_at` |
| Map: consolidated route line | `HL_ROUTE_LINE_V.ROUTE_GEOJSON`: a GeoJSON LineString, buyer → farms → buyer, for an APEX Map line layer (geometry column type GeoJSON) |
| Map: pickup pins and destination | `HL_ROUTE_STOP_V`: `latitude`, `longitude`, `stop_type` (`FARM` or `DESTINATION`), `stop_no`, `ui_status` (solid pin for `MATCHED`, hollow for `PENDING`) |
| Map: separate-trip comparison lines | `HL_ROUTE_STOP_V` farm rows: from (`latitude`, `longitude`) to (`dest_lat`, `dest_lon`), with `direct_km` |
| Pickup order table | `HL_ROUTE_STOP_V` order by `stop_no`: `stop_name`, `place`, `load_kg`, `leg_km`, `cumulative_km`, `arrive_at` |
| Vehicle load ("1,900 kg of 3,000 kg") | `HL_ROUTE_LINE_V` total kg (destination row `load_kg`) against `TRUCK_CAPACITY_KG` / `PICKUP_CAPACITY_KG` in `HL_SETTINGS` |

The legs of one trip add up to `aggregated_km / trips`. Older columns in `HL_DEMAND_SUMMARY_V` (`vehicle_type`,
`trips`, `km_saved`, `co2_saved_kg`) still work.

### 8 · Sustainability impact — Ready

`select * from hl_impact_metrics_v order by sort_order` — one row per StatCard:

| Column | Use |
|---|---|
| `metric_group` | `MARKET_ACCESS` or `WASTE_EMISSIONS` section |
| `metric_key` | Stable key: `PRODUCE_SOURCED`, `FARMERS_REACHED`, `DEMANDS_SERVED`, `AGREEMENTS_RECORDED`, `INCOME_UPLIFT`, `LOSS_AVOIDED`, `DISTANCE_SAVED`, `CO2_AVOIDED`, `TRIPS_REPLACED` |
| `label`, `value`, `unit` | Card text |
| `provenance` | ProvenanceTag. `INCOME_UPLIFT` is `sourced` while every broker price it uses (crops in current orders, above Grade C) is published or from the market interviews, else `demo`; its `method` lists those prices and sources |
| `method` | "How this is calculated" note |

### Demo dataset and reset — Ready

The database ships with the canvas story (fictional people, dates relative to today):

| Order (Kijani Fresh Grocers, Westlands) | State after a reset |
|---|---|
| 2 t Grade A Roma tomatoes, KES 75/kg, in 14 days (`hl_demo.featured_demand_id`) | 1,200 kg confirmed (Wanjiru Muthoni, Peter Kariuki), 700 kg pending (Grace Wambui, Esther Wangui), 100 kg open; Joseph Mugo not matched (harvest starts after delivery) |
| 1.2 t Grade A onions in 19 days | Filled and confirmed |
| 400 kg Grade A green peppers in 9 days | Filled and confirmed |
| 800 kg Grade B carrots in 2 days | Confirmed, route `DISPATCHED` (in transit) |
| 600 kg Grade A Roma tomatoes, 2 days ago | Delivered, `CLOSED` |

The four tomato farms also hold 640 kg of Grade B and 310 kg of Grade C, which appear in grade routing with suggested outlets.

Before a rehearsal or the pitch: `begin hl_demo.reset; end;` (commits). A "Reset demo data" button on an operations page can call the same. The agreement ledger is never cleared, so earlier rehearsal confirmations remain in it.

### Farmer data rights — Ready

Kenya Data Protection Act, 2019: consent at sign-up, a copy of your data, and deletion. Source:
`db/13_farmer_api.sql`. A farmer may call these for their own account; `OPS` for anyone (`-20603` otherwise).

| Use | Call |
|---|---|
| Sign-up consent checkbox | Show the latest `HL_CONSENT_TEXTS.CONSENT_TEXT`. Saving `consent_given = 'Y'` on `HL_FARMERS` (form or insert) stamps `consent_version` and `consent_at` automatically. |
| Record consent to a specific notice | `hl_farmer_api.record_consent(p_farmer_id, p_consent_version default latest)` |
| "Download my data" | `hl_farmer_api.export_data(p_farmer_id)` returns a JSON CLOB; the signed-in farmer's copy is `HL_MY_DATA_V.DATA_JSON` |
| "Delete my account" | `hl_farmer_api.delete_account(p_farmer_id)`; sign the farmer out afterwards (their login no longer maps to a party) |
| What a ledger purge would delete (operations) | `HL_LEDGER_PURGE_V`: `cutoff`, `due_erasures`, `rows_to_delete`, `erased_rows`, `other_rows`, `next_due` |
| Purge expired ledger rows (operations) | `hl_farmer_api.purge_ledger` returns rows deleted and logs the purge in `HL_LEDGER_PURGES`; steps in `docs/operations.md` |

`export_data` keys: `exported_at`, `farmer`, `consent` (`given`, `version`, `given_at`, `notice_text`), `logins`,
`harvests`, `matches`, `allocations`, `agreement_ledger`, `retention`.

What `delete_account` does, in one transaction (nothing is changed if it fails):

1. Logs the request in `HL_ERASURES` (no name or phone: farmer ID, pseudonym `Erased farmer #n`, the harvest IDs
   that link to ledger rows, and `PURGE_AFTER` = newest ledger row naming the farmer + 16 days).
2. Replaces the farmer's name and phone with the pseudonym, then declines their confirmed matches, so the ledger
   records each agreement ending (`REJECTED`) without the real name.
3. Deletes their harvests without a delivered match (with their matches, allocations and pickup stops) and their
   login mapping in `HL_APP_USERS`, and re-matches the freed demand to other farms. Dispatched and closed routes are
   not re-planned; the name in their stop list is replaced by the pseudonym.
4. Keeps delivered history: harvests with a `DELIVERED` match stay (status `HARVESTED`, closed to matching) with
   only their delivered matches, so closed demands keep their delivered kg and the impact figures do not drop.
   The farmer row then stays as a pseudonymous stub (`full_name` = pseudonym, placeholder phone, no village,
   cooperative or consent, location rounded to 0.1°, `erased_at` set) and its pickup stops are pseudonymised the
   same way. A farmer with no delivered history has the row deleted.

Afterwards the farmer is in no view except `HL_AGREEMENTS_V` (a stub appears only as `Erased farmer #n` on delivered
orders). Ledger rows written **before** the deletion keep the real name and phone, because a blockchain table
cannot be updated and `NO DELETE UNTIL 16 DAYS AFTER INSERT`. Once `PURGE_AFTER` passes, `purge_ledger` deletes them
with `DBMS_BLOCKCHAIN_TABLE.DELETE_EXPIRED_ROWS`. That call can only trim the ledger by age, so it also deletes
**every other** party's rows as old as the newest one being purged. This is accepted and run monthly by operations
(`docs/operations.md`, which explains the decision). It sets `PURGED_AT` on each erasure whose rows are gone.
Calling `delete_account` or `export_data` again for a deleted farmer raises `-20606`.

In the demo, `hl_demo.reset` brings deleted demo farmers back and re-maps `FARMER_DEMO` to Wanjiru Muthoni.

### Agreement ledger — Ready

`HL_AGREEMENTS_V`: `chain_seq`, `recorded_at`, `event` (`ACCEPTED`, `REJECTED`, `DELIVERED`), `farmer_name`, `buyer_name`, `crop_name`, `grade`, `quantity_kg`, `price_per_kg`, `value_kes`, `recorded_by`, `row_hash`, `row_hash_short`. Read only; rows cannot be changed.

## Errors

| Code | Raised by | Message (shown to the user) |
|---|---|---|
| -20101 | `run` | Demand is closed or cancelled |
| -20111 | `confirm` | Match is not awaiting a farmer answer |
| -20112 | `decline` | Match cannot be declined |
| -20201 | `create_demand` | Quantity must be more than 0 kg and at most 50,000 kg |
| -20202 | `create_demand` | Delivery date must be at least 7 days from today |
| -20203 | `create_demand` | Grade must be A, B or C |
| -20204 | `create_demand` | Price must be more than KES 0/kg |
| -20205 | `create_demand` | Give both delivery latitude and longitude, or neither |
| -20206 | `cancel` | Demand is already closed or cancelled |
| -20207 | `cancel`, `publish` | Demand does not exist |
| -20208 | `create_demand`, `save_draft` | Receiving time must be 06:00–10:00, 10:00–14:00 or 14:00–18:00 |
| -20209 | `save_draft`, `publish` | Demand is not a draft |
| -20211 | `register`, `update_estimate` | Expected quantity must be more than 0 kg |
| -20212 | `register`, `update_estimate` | Harvest end must be on or after harvest start |
| -20213 | `register`, `update_estimate` | Harvest start cannot be in the past |
| -20214 | `register` | Grade must be A, B or C |
| -20215 | `update_estimate` | Harvest already promised to a buyer |
| -20216 | `update_estimate` | Harvest does not exist |
| -20301 | `hl_demo.seed` | Demo tables are not empty; use `hl_demo.reset` |
| -20401 | `hl_alloc_pkg.allocate` | Only *n* kg of this lot is left to allocate |
| -20402 | `hl_alloc_pkg.allocate` | This outlet does not take that grade |
| -20403 | `hl_alloc_pkg.allocate` | Quantity must be more than 0 kg |
| -20404 | `hl_alloc_pkg.allocate` | Harvest does not exist |
| -20405 | `hl_alloc_pkg.allocate` | Outlet does not exist |
| -20406 | `hl_alloc_pkg.remove` | Allocation does not exist |
| -20501 | `hl_auth.register_user` | Role must be BUYER, FARMER or OPS |
| -20502 | `hl_auth.register_user` | No buyer or farmer with that name |
| -20601 | `hl_farmer_api` | Farmer does not exist |
| -20602 | `record_consent` | Consent notice does not exist |
| -20603 | `hl_farmer_api` | You can only see or delete your own farmer account |
| -20604 | Saving consent on `HL_FARMERS` | No consent notice has been published |
| -20605 | `purge_ledger` | Only operations can purge the agreement ledger |
| -20606 | `hl_farmer_api` | Farmer has already been deleted |
| -20611 | `hl_ai` | Match does not exist |
| -20612 | `hl_ai` | Language must be en (English) or sw (Kiswahili) |
| -20621 | `apply_interview_prices` | Only operations can change crop prices |
| -20622 | `apply_interview_prices` | Minimum number of observations must be at least 1 |

The app's error handling function, `hl_apex_error.handle` (`db/12_apex_error.sql`), shows these messages without
the `ORA-20xxx:` prefix or stack, in the page notification. It is set on every build by `scripts/install_app.py`,
so pages need no extra code: let the error propagate from the page process. To show a message next to a field,
raise it from a validation or use `apex_error.add_error` with the item name. Common constraint errors from forms
(duplicate record, related record missing, record still in use) are reworded too.

## Changing the backend

- Open backend work is tracked as GitHub issues with the `backend` label.
- Every change runs `db/tests/run.sh` (also in CI on pull requests that touch `db/`). Add a test in `db/tests/`
  for any new view column, procedure or rule a page depends on.
- Update this file in the same pull request when a contract view or procedure changes.
