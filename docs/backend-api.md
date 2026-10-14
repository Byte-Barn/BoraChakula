# HarvestLink backend API for the frontend

This is the contract between the canvas screens (APEX pages) and the database.
**Pages read the views and change data only by calling the procedures below.**
Tables behind them may change; the names, parameters and columns here will not
change without a note in this file.

- Database: Oracle Autonomous AI Database 26ai, schema `HARVESTLINK` (APEX parsing schema).
- Source: `db/02_match_pkg.sql` (matching), `db/06_agreements.sql` (ledger), `db/07_api.sql` (APIs and contract views).
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
| `reason_*_state` | `ok`, `warn` | MatchCard reason icon |
| `provenance` | `live`, `simulated`, `demo` | ProvenanceTag of the same name |

## Screen by screen

### 1 · Landing page (public) — Ready

| Needs | Source |
|---|---|
| Example-in-numbers strip | `HL_IMPACT_METRICS_V` rows `PRODUCE_SOURCED`, `FARMERS_REACHED`, `DISTANCE_SAVED`, `LOSS_AVOIDED` (`value`, `unit`, `provenance`) |
| Example demand card and fulfilment bar | `HL_FULFIL_V` for one demand (`target_kg`, `matched_kg`, `pending_kg`, `unmatched_kg`) |

The page must be public (no login): read-only queries only, label figures "Illustrative figures from the demo dataset".

### 2 · Farmer: register harvest (phone) — Ready

```sql
-- Page process "Register harvest" (P20)
:P20_HARVEST_ID := hl_harvest_api.register(
  p_farmer_id       => :P20_FARMER_ID,     -- from the session once roles land (Planned); a select list until then
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
| Demands table | `HL_FULFIL_V` filtered by `buyer_id` (`crop_name`, `grade_required`, `target_kg`, `matched_kg + pending_kg` as sourced, `need_by_date`, `status`) |
| Stat cards | `count(*)` active demands, `sum(matched_kg)` confirmed supply, `sum(pending_kg)` awaiting farmers, all from `HL_FULFIL_V` for the buyer |
| "Farmers have not confirmed" alert | `HL_MATCH_V` where `ui_status = 'PENDING'` for the buyer's demands |
| Route preview | `HL_MATCH_V` (`farmer_lat`, `farmer_lon`, `stop_order`, `ui_status`) plus the demand's route (see 7) |

Until roles land (Planned), pass the buyer with a select list or page item.

### 4 · Post a demand — Ready

```sql
-- Page process "Post demand" (P11)
:P11_DEMAND_ID := hl_demand_api.create_demand(
  p_buyer_id     => :P11_BUYER_ID,
  p_crop_id      => :P11_CROP_ID,
  p_grade        => :P11_GRADE,
  p_quantity_kg  => :P11_QTY_KG,          -- tonnes × 1000 in the page
  p_price_per_kg => :P11_PRICE_PER_KG,
  p_need_by_date => :P11_DELIVERY_DATE,   -- at least 7 days from today
  p_delivery_lat => :P11_LAT,             -- optional; buyer location when null
  p_delivery_lon => :P11_LON,
  p_notes        => :P11_NOTES);
-- then branch to the matching page with P12_DEMAND_ID = :P11_DEMAND_ID
```

Review panel values are computed in the page (`qty × price` = order value). Receiving time window and "save draft" are not stored yet (Planned).

### 5 · Matching and aggregation — Ready

| Needs | Source |
|---|---|
| Header and fulfilment bar | `HL_FULFIL_V` where `demand_id = :P12_DEMAND_ID` |
| Ranked farmer cards | `HL_MATCH_V` where `demand_id = :P12_DEMAND_ID and ui_status <> 'DECLINED' order by rank_no` |
| "Not matched" card | `HL_MATCH_V` where `ui_status = 'DECLINED'` (farmers who said no) |
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

### 6 · Grade routing — Ready (read), Planned (allocation)

Read `HL_GRADE_ROUTING_V`: unallocated produce per harvest with the recommended channel and `suggested_buyer`, `suggested_buyer_type`, `suggested_buyer_km`. Editable outlet allocations with a no-double-counting guard (`HL_ALLOC_PKG`) are Planned.

### 7 · Logistics and pickup route — Ready (summary), Planned (stops table)

`HL_DEMAND_SUMMARY_V` per demand: `vehicle_type` (`TRUCK`, `PICKUP` or `DIRECT`), `trips`, `aggregated_km`, `individual_km`, `km_saved`, `co2_saved_kg`. Pickup pins and order: `HL_MATCH_V` (`farmer_lat`, `farmer_lon`, `stop_order`, `ui_status`); destination: buyer location. A per-stop table with times (`HL_ROUTE_STOP`) is Planned.

### 8 · Sustainability impact — Ready

`select * from hl_impact_metrics_v order by sort_order` — one row per StatCard:

| Column | Use |
|---|---|
| `metric_group` | `MARKET_ACCESS` or `WASTE_EMISSIONS` section |
| `metric_key` | Stable key: `PRODUCE_SOURCED`, `FARMERS_REACHED`, `DEMANDS_SERVED`, `AGREEMENTS_RECORDED`, `INCOME_UPLIFT`, `LOSS_AVOIDED`, `DISTANCE_SAVED`, `CO2_AVOIDED`, `TRIPS_REPLACED` |
| `label`, `value`, `unit` | Card text |
| `provenance` | ProvenanceTag |
| `method` | "How this is calculated" note |

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
| -20207 | `cancel` | Demand does not exist |
| -20211 | `register`, `update_estimate` | Expected quantity must be more than 0 kg |
| -20212 | `register`, `update_estimate` | Harvest end must be on or after harvest start |
| -20213 | `register`, `update_estimate` | Harvest start cannot be in the past |
| -20214 | `register` | Grade must be A, B or C |
| -20215 | `update_estimate` | Harvest already promised to a buyer |
| -20216 | `update_estimate` | Harvest does not exist |

In APEX, map these to inline errors with an Error Handling Function, or let the default handler show the message.

## Planned backend PRs

| PR | Adds | Unblocks |
|---|---|---|
| Roles and demo users | Buyer, farmer and operations logins linked to `buyer_id` / `farmer_id`; `G_PARTY_ID`; authorization helpers | Per-role navigation, "my demands", "my harvests" |
| Demo dataset and reset | Kirinyaga story from the canvas (Kijani Fresh Grocers, 2 t Roma tomatoes); `hl_demo.reset` | Rehearsals that start clean; numbers that match the slides |
| Grade allocation | Lots, outlets, allocations, `HL_ALLOC_PKG.allocate` with the sum ≤ lot guard | Grade routing screen edits |
| Route stops | `HL_ROUTE_STOP` with order, times and per-leg km; separate-trip lines for the map | Logistics screen table and map |
| Demand extras | Receiving time window, draft demands | Post-a-demand form fields |
