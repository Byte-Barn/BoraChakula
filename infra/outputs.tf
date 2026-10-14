output "autonomous_database_id" {
  value = oci_database_autonomous_database.harvestlink.id
}

output "db_version" {
  value = oci_database_autonomous_database.harvestlink.db_version
}

output "apex_url" {
  value = oci_database_autonomous_database.harvestlink.connection_urls[0].apex_url
}

output "database_actions_url" {
  value = oci_database_autonomous_database.harvestlink.connection_urls[0].sql_dev_web_url
}

output "wallet_path" {
  value = local_sensitive_file.wallet_zip.filename
}

output "app_url" {
  value = replace(lower(oci_database_autonomous_database.harvestlink.connection_urls[0].apex_url), "/ords/apex", "/ords/r/harvestlink/harvestlink/")
}
