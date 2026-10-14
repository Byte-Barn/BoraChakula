# HarvestLink APEX application

The app is defined as an Oracle APEX 26.1 **Application Blueprint** and built without App Builder:

| Path | What it is |
|---|---|
| `harvestlink-blueprint.md` | Source of truth: pages, regions, forms, LOVs, menu (Oracle blueprint grammar v26.1) |
| `apexlang/` | APEXlang application generated from the blueprint by `APEX_GENDEV.PROCESS_BLUEPRINT` |
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

## Build and install

`terraform apply` in `infra/` runs this automatically whenever the blueprint changes. By hand:

```bash
source ~/.config/harvestlink/secrets.env
python scripts/install_app.py --wallet infra/.wallet/wallet.zip --check-only   # validate + regenerate apexlang/
python scripts/install_app.py --wallet infra/.wallet/wallet.zip --app-id 100   # also install
```

Install uses SQLcl 26.x (`apex validate` / `apex import`), because APEX 26.1 cannot import
APEXlang through `APEX_APPLICATION_INSTALL`. Edit the blueprint and `theme/`, not the generated files: the installer adds the stylesheet
(as a static application file loaded after the theme CSS) and the icons on every build.
