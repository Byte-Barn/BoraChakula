provider "oci" {
  config_file_profile = var.config_file_profile
  region              = var.region
}

# Always Free Autonomous AI Database with APEX workload
resource "oci_database_autonomous_database" "harvestlink" {
  compartment_id = var.tenancy_ocid
  db_name        = var.db_name
  display_name   = "HarvestLink"
  db_workload    = "APEX"
  is_free_tier   = true
  admin_password = var.admin_password

  # Always Free without an IP allow-list requires mutual TLS (wallet)
  is_mtls_connection_required = true

  lifecycle {
    ignore_changes = [admin_password]
  }
}

# Client wallet used by scripts/bootstrap_db.py to connect as ADMIN
resource "oci_database_autonomous_database_wallet" "harvestlink" {
  autonomous_database_id = oci_database_autonomous_database.harvestlink.id
  password               = var.wallet_password
  generate_type          = "SINGLE"
  base64_encode_content  = true
}

resource "local_sensitive_file" "wallet_zip" {
  content_base64  = oci_database_autonomous_database_wallet.harvestlink.content
  filename        = "${path.module}/.wallet/wallet.zip"
  file_permission = "0600"
}
