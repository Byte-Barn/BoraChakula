# HarvestLink infrastructure (Oracle Cloud)

One `terraform apply` builds the whole stack on OCI Always Free:

| Step | Resource | What it does |
|---|---|---|
| 1 | `oci_database_autonomous_database.harvestlink` | Always Free Autonomous AI Database (Transaction Processing, includes APEX and ORDS) |
| 2 | `oci_database_autonomous_database_wallet.harvestlink` | mTLS client wallet, written to `infra/.wallet/wallet.zip` |
| 3 | `terraform_data.database` | `scripts/bootstrap_db.py`: schema user, APEX workspace, developer and judge logins, tables, matching engine, views, demo data, auto-match triggers |
| 4 | `terraform_data.apex_app` | `scripts/install_app.py`: generates the APEX app from `apex/harvestlink-blueprint.md` and imports it with SQLcl |

Steps 3 and 4 re-run only when their sources change (`db/*.sql` and the bootstrap script, or the
blueprint and the install script). With `reset_data = true` (default), a change under `db/`
drops and reinstalls the schema, which resets the data to the demo seed.

## Prerequisites

- OCI account with an API key in `~/.oci/config` (profile `DEFAULT`)
- Terraform 1.5+
- Python 3 with `pip install -r requirements.txt` (default path `~/.venvs/harvestlink/bin/python`)
- SQLcl 26.x and Java 17+ (default path `~/.local/opt/sqlcl/bin/sql`)
- A secrets file such as `~/.config/harvestlink/secrets.env`, outside the repo:

```bash
export TF_VAR_admin_password=...   # ADMIN: 12-30 chars, upper, lower, number
export TF_VAR_wallet_password=...
export HL_ADMIN_PASSWORD=$TF_VAR_admin_password
export HL_WALLET_PASSWORD=$TF_VAR_wallet_password
export HL_SCHEMA_PASSWORD=...      # HARVESTLINK schema owner
export HL_APEX_USER=... HL_APEX_PASSWORD=... HL_APEX_EMAIL=...   # workspace developer
export HL_DEMO_USER=... HL_DEMO_PASSWORD=...                     # app-only login for judges
```

Secrets never pass through Terraform configuration; the scripts read them from the environment.
Terraform state still holds the ADMIN and wallet passwords, so it stays git-ignored.

## Deploy

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # set tenancy_ocid and region
source ~/.config/harvestlink/secrets.env
terraform init
terraform apply
terraform output app_url
```

To force a rebuild of one layer: `terraform apply -replace=terraform_data.apex_app`
(or `terraform_data.database`, which also re-imports the app).

## Notes

- An Always Free tenancy allows two free Autonomous Databases. This config imported the
  console-created `HarvestLinkStrathmore` database instead of creating a second one.
- Always Free databases stop after 7 days without activity; start them again from the console
  or with `oci db autonomous-database start`.
