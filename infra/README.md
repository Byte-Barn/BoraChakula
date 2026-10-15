# HarvestLink infrastructure (Oracle Cloud)

One `terraform apply` builds the whole stack on OCI Always Free:

| Step | Resource | What it does |
|---|---|---|
| 1 | `oci_database_autonomous_database.harvestlink` | Always Free Autonomous AI Database (Transaction Processing, includes APEX and ORDS) |
| 2 | `oci_database_autonomous_database_wallet.harvestlink` | mTLS client wallet, written to `infra/.wallet/wallet.zip` |
| 3 | `terraform_data.database` | `scripts/bootstrap_db.py`: schema user, APEX workspace, developer, judge and role demo logins, tables, matching engine, views, demo data, auto-match triggers |
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
export HL_ROLE_DEMO_PASSWORD=...  # BUYER_DEMO, FARMER_DEMO and OPS_DEMO logins
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

## Continuous deployment (GitHub Actions)

`.github/workflows/deploy.yml` deploys `main` to the same database whenever `db/`, `apex/` or `scripts/` change:

1. **Backend tests**: `db/tests/run.sh` on Oracle Database 23ai Free. A failure stops the deploy.
2. **Deploy**, in the `production` environment (only `main` may deploy):
   - `db/*.sql` or `scripts/bootstrap_db.py` changed: `bootstrap_db.py --reset` (schema and demo data rebuilt),
     then the app. The reset keeps Select AI on if it was on and its profile and credential exist;
     `enable_select_ai.py` also runs if the `HL_AI_API_KEY` secret is set.
   - `apex/` or `scripts/install_app.py` changed: `install_app.py` rebuilds and imports app 100.
   - The landing page must answer HTTP 200 afterwards.

Run it by hand from **Actions → Deploy to OCI → Run workflow** (choose database and/or app).

Secrets live in the `production` environment and are set with `gh`, piped from the secrets file so values never
appear on screen:

```bash
source ~/.config/harvestlink/secrets.env
for n in HL_ADMIN_PASSWORD HL_WALLET_PASSWORD HL_SCHEMA_PASSWORD HL_APEX_USER HL_APEX_PASSWORD HL_APEX_EMAIL \
         HL_DEMO_USER HL_DEMO_PASSWORD HL_ROLE_DEMO_PASSWORD; do
  printf '%s' "${!n}" | gh secret set "$n" --env production
done
base64 -w0 infra/.wallet/wallet.zip | gh secret set HL_WALLET_ZIP_B64 --env production
# optional, switches Select AI on after each schema rebuild
printf '%s' "$HL_AI_API_KEY" | gh secret set HL_AI_API_KEY --env production
gh variable set HL_AI_PROVIDER --env production --body openai
```

Re-run the wallet line whenever Terraform regenerates the wallet (for example after a wallet password change).

Terraform and CI run the same scripts. After CI has deployed, a local `terraform apply` sees new source hashes
and runs them once more, which is harmless but resets the demo data. Use Terraform for the database and wallet,
and CI for schema and app changes.

## Notes

- An Always Free tenancy allows two free Autonomous Databases. This config imported the
  console-created `HarvestLinkStrathmore` database instead of creating a second one.
- Always Free databases stop after 7 days without activity; start them again from the console
  or with `oci db autonomous-database start`.
