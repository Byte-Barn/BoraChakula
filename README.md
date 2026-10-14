# HarvestLink

**Sell before you harvest.** HarvestLink by Bora Chakula is a demand-first agricultural marketplace for Kenya.
Buyers post what they need before harvest; the platform combines smallholder farmers to fill each order,
finds an outlet for every grade, and sends one truck instead of many.

Built for the Green Tech Hackathon 2026 (Strathmore University) on Oracle Cloud Infrastructure:
Oracle APEX on an Always Free Autonomous AI Database, with the matching engine in PL/SQL next to the data.

| | |
|---|---|
| Live app | <https://gc0208e4d90b947-harvestlinkstrathmore.adb.eu-frankfurt-1.oraclecloudapps.com/ords/r/harvestlink/harvestlink/> (sign-in required; ask the team for the judge login) |
| Architecture | [`docs/architecture.md`](docs/architecture.md) |
| Backend API for the frontend | [`docs/backend-api.md`](docs/backend-api.md) |
| Hackathon plan | [`docs/HarvestLink_Hackathon_Plan.pdf`](docs/HarvestLink_Hackathon_Plan.pdf) |

## The problem

Smallholder farmers grow without knowing who will buy. At harvest they sell to brokers at the farm gate, lower
grades go unsold, and each farmer hires transport alone. Buyers such as grocers, schools and processors cannot
get steady volume from any single small farm.

## How HarvestLink works

1. **A buyer posts a demand**: crop, quantity, grade, price, date and place, weeks before harvest.
2. **Farmers are combined**: each farm is ranked on quantity, grade, harvest window and distance, then added up
   until the order is full. Every match shows its reasons, never a score alone.
3. **Every grade has a buyer**: Grade A to the buyer, B to local markets and schools, C to processors instead of the bin.
4. **One truck collects it**: a shared pickup route, with the kilometres, loss and CO₂ it saved.
5. **Agreements are tamper-evident**: each farmer's confirmation is written to an Oracle blockchain table.

## Built on Oracle

| Oracle service | Used for |
|---|---|
| Autonomous AI Database 26ai (Always Free, Transaction Processing) | All data, plus the matching engine, routing and impact maths as PL/SQL |
| Oracle APEX 26.1 | The web app, generated from an Application Blueprint and imported with SQLcl |
| ORDS | Serves the app from the database |
| Blockchain tables | `HL_AGREEMENTS`: append-only, hash-chained record of farmer agreements |
| OCI Terraform provider | Database, wallet and the full app build in one `terraform apply` |

## Repository layout

| Path | Contents |
|---|---|
| `db/` | Schema, matching engine (`HL_MATCH_PKG`), views, agreement ledger, frontend API, demo data ([`db/README.md`](db/README.md)) |
| `apex/` | APEX Application Blueprint, generated APEXlang app and theme ([`apex/README.md`](apex/README.md)) |
| `infra/` | Terraform for the whole stack on OCI ([`infra/README.md`](infra/README.md)) |
| `scripts/` | `bootstrap_db.py` (schema, workspace, users, data) and `install_app.py` (build and import the app) |
| `docs/` | Architecture, backend API contract, hackathon plan |

## Quick start

**Run the database locally** (Oracle Database 23ai Free in Docker, no APEX):

```bash
docker run -d --name harvestlink-oracle -p 127.0.0.1:1521:1521 \
  -e ORACLE_PASSWORD=<pw> -e APP_USER=harvestlink -e APP_USER_PASSWORD=<pw> \
  gvenzl/oracle-free:23-slim-faststart
docker cp db harvestlink-oracle:/tmp/db
docker exec -w /tmp/db harvestlink-oracle sqlplus harvestlink/<pw>@localhost/FREEPDB1 @install.sql
```

**Deploy everything to OCI** (database, schema, demo data and app):

```bash
python -m venv ~/.venvs/harvestlink && ~/.venvs/harvestlink/bin/pip install -r requirements.txt
source ~/.config/harvestlink/secrets.env    # passwords; never committed
cd infra && terraform init && terraform apply
terraform output app_url
```

Prerequisites, secrets and options are in [`infra/README.md`](infra/README.md).

## Working on the code

- **Backend** (database, PL/SQL, views, Terraform, scripts): one branch and one pull request per change.
  Keep [`docs/backend-api.md`](docs/backend-api.md) current whenever a view or procedure the pages use changes.
- **Frontend** (APEX pages built from the design canvas): read data from the contract views and change it only
  through the API procedures in `docs/backend-api.md`. Do not write SQL against the tables from pages.
- **APEX app**: edit `apex/harvestlink-blueprint.md` and `apex/theme/`, not the generated `apex/apexlang/`.
- **Tests**: `db/tests/run.sh` installs the schema into a throwaway user on Oracle 23ai Free in Docker and runs
  the backend tests (60 checks); CI runs it on every pull request that touches `db/`.
- **Demo data**: `begin hl_demo.reset; end;` restores the demo story before a rehearsal.
- Never commit passwords, wallets, `terraform.tfvars` or Terraform state (all git-ignored).

## Honest numbers

Every impact figure is labelled by where it comes from: **live** (computed from records), **simulated**
(prototype stand-in, such as straight-line × 1.3 road distances) or **demo** (illustrative factor or placeholder
price). Prices, the 30% baseline loss rate and emission factors are placeholders until calibrated with market
interviews. People and businesses in the demo data are fictional.
