# HarvestLink APEX application

The app is defined as an Oracle APEX 26.1 **Application Blueprint** and built without App Builder:

| Path | What it is |
|---|---|
| `harvestlink-blueprint.md` | Source of truth: pages, regions, forms, LOVs, menu (Oracle blueprint grammar v26.1) |
| `apexlang/` | APEXlang application generated from the blueprint by `APEX_GENDEV.PROCESS_BLUEPRINT` |
| `pages/` | Canvas screens written in APEXlang, copied into `apexlang/` on every build (blueprints cannot call the backend API) |
| `theme/harvestlink.css` | HarvestLink "Field Ledger" styling over Universal Theme: forest on ivory, Fraunces and IBM Plex, hairline panels |
| `theme/icons/` | App icons drawn from the HarvestLink leaf mark |

## Pages

| # | Page | What it does |
|---|---|---|
| 1 | Impact Dashboard | KPIs (kg matched, farmers reached, waste avoided, km and CO2 saved, income uplift) and charts |
| 2 / 3 | Buyer Demands / Demand Form | Buyers post produce needs before harvest |
| 4 / 5 | Farmer Harvests / Harvest Form | Farmers register expected harvests |
| 6 | Match Planner | Pick a demand: matched farmers with reasons, pickup map, route savings |
| 7 | Grade Routing | Unallocated produce with recommended channel and suggested buyer per grade |
| 8 / 9 | Farmers / Farmer Form | Farmer directory with coordinates and consent |
| 10 / 11 | Buyers / Buyer Form | Buyer directory with accepted grades and verification |

Saving or deleting a demand, harvest or farmer location re-runs matching automatically
(`db/05_auto_match.sql`), so there is no separate "run matching" step.

## Canvas screens (`pages/`)

The screens from the design canvas, built on the contract in [`docs/backend-api.md`](../docs/backend-api.md):
they read the contract views and change data only through the API packages. The navigation entry of each shows
for the roles that use it (`hl_auth`).

| # | Screen | Roles | Reads | Calls |
|---|---|---|---|---|
| 20 | My farm | Farmer, operations | `HL_MY_OFFERS_V`, `HL_MY_HARVESTS_V`, `HL_CONSENT_TEXTS`, `HL_MY_DATA_V` | `hl_match_pkg.confirm` / `decline`, `hl_harvest_api.register`, `hl_farmer_api.delete_account` |
| 30 | My demands | Buyer, operations | `HL_FULFIL_V` (the buyer's own) | |
| 31 | Post a demand | Buyer, operations | | `hl_demand_api.create_demand` / `save_draft` / `publish` |
| 32 | Matches | Buyer, operations | `HL_FULFIL_V`, `HL_MATCH_V`, `HL_NEAR_MISS_V`, `hl_ai` | `hl_match_pkg.confirm` / `decline` / `run` |
| 40 | Route by grade | Operations | `HL_GRADE_ALLOCATION_V`, `HL_GRADE_ROUTING_V`, `HL_ALLOCATIONS_V` | `hl_alloc_pkg.allocate` / `remove`, `hl_demo.reset` |
| 41 | Logistics | Buyer, operations | `HL_ROUTE_LINE_V` (map line), `HL_ROUTE_STOP_V` (pins, pickup order) | |
| 42 | Impact | Everyone | `HL_IMPACT_METRICS_V` | |
| 50 | Welcome (public, no login) | Anyone | `HL_IMPACT_METRICS_V`, `HL_FULFIL_V` (featured demand) | |

Each `p*.apx` file is one page. `navigation.apx` holds their menu entries and `lovs.apx` extra lists of values;
the installer adds both to the generated shared components. Cards are Content Row template components whose
description is HTML built in the page query (values escaped with `apex_escape.html`); the classes it uses
(`hl-fulfil`, `hl-badge`, `hl-reason`, `hl-prov`, ...) are styled in `theme/harvestlink.css`. Page numbers must
not clash with blueprint pages (the installer stops if they do).

APEX enforces an app-wide "must not be public user" scheme even on public pages, so the installer drops it to let
the landing page (50) open without a login. Every other page sets the same check itself, and the installer stops
if a non-public page does not.

## Build and install

`terraform apply` in `infra/` runs this automatically whenever the blueprint changes. By hand:

```bash
source ~/.config/harvestlink/secrets.env
python scripts/install_app.py --wallet infra/.wallet/wallet.zip --check-only   # validate + regenerate apexlang/
python scripts/install_app.py --wallet infra/.wallet/wallet.zip --app-id 100   # also install
# a preview copy beside app 100 (aliases must be unique in the workspace)
python scripts/install_app.py --wallet infra/.wallet/wallet.zip --app-id 200 --alias HARVESTLINK-200 --name "HarvestLink preview 200"
```

On Windows, keep `.apx` files on LF line endings (`.gitattributes` does this for checkouts): SQLcl's APEXlang
parser rejects CRLF.

Install uses SQLcl 26.x (`apex validate` / `apex import`), because APEX 26.1 cannot import
APEXlang through `APEX_APPLICATION_INSTALL`. Edit the blueprint and `theme/`, not the generated files: the installer adds the stylesheet
(as a static application file loaded after the theme CSS), the icons and the error handling function
(`hl_apex_error.handle`) on every build.
