# Everything inside the database is built by the repo's scripts, run from here so
# one `terraform apply` goes from an empty tenancy to a working app. Each step
# re-runs only when its source files change.
#
# Secrets are NOT passed through Terraform; the scripts read HL_* variables from
# the environment (source ~/.config/harvestlink/secrets.env before applying).

locals {
  repo_root   = abspath("${path.module}/..")
  wallet_path = abspath(local_sensitive_file.wallet_zip.filename)

  db_sources = concat(
    [for f in sort(fileset(local.repo_root, "db/*.sql")) : "${local.repo_root}/${f}"],
    ["${local.repo_root}/scripts/bootstrap_db.py"],
  )
  app_sources = concat(
    [
      "${local.repo_root}/apex/harvestlink-blueprint.md",
      "${local.repo_root}/scripts/install_app.py",
    ],
    [for f in sort(fileset(local.repo_root, "apex/theme/**")) : "${local.repo_root}/${f}"],
    [for f in sort(fileset(local.repo_root, "apex/pages/**")) : "${local.repo_root}/${f}"],
  )
}

# Schema user, APEX workspace, developer and judge logins, tables, matching
# engine, views, demo data and auto-match triggers
resource "terraform_data" "database" {
  triggers_replace = {
    database = oci_database_autonomous_database.harvestlink.id
    sources  = sha256(join("", [for f in local.db_sources : filesha256(f)]))
  }

  provisioner "local-exec" {
    working_dir = local.repo_root
    command     = "${pathexpand(var.python)} scripts/bootstrap_db.py --wallet ${local.wallet_path}${var.reset_data ? " --reset" : ""}"
    environment = {
      PYTHONUNBUFFERED = "1"
    }
  }
}

# APEX app generated from the blueprint and imported with SQLcl
resource "terraform_data" "apex_app" {
  triggers_replace = {
    database = terraform_data.database.id
    sources  = sha256(join("", [for f in local.app_sources : filesha256(f)]))
    app_id   = var.app_id
  }

  provisioner "local-exec" {
    working_dir = local.repo_root
    command     = "${pathexpand(var.python)} scripts/install_app.py --wallet ${local.wallet_path} --app-id ${var.app_id}"
    environment = {
      SQLCL            = pathexpand(var.sqlcl)
      PYTHONUNBUFFERED = "1"
    }
  }
}
