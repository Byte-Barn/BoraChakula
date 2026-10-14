variable "tenancy_ocid" {
  description = "Tenancy OCID (the root compartment is used for the database)"
  type        = string
}

variable "region" {
  description = "OCI home region, e.g. eu-frankfurt-1"
  type        = string
}

variable "config_file_profile" {
  description = "Profile in ~/.oci/config used for API key authentication"
  type        = string
  default     = "DEFAULT"
}

variable "admin_password" {
  description = "ADMIN password: 12-30 chars, upper, lower, number; no double quote or 'admin'"
  type        = string
  sensitive   = true
}

variable "wallet_password" {
  description = "Password protecting the downloaded client wallet"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name (letters and numbers only, max 30 chars)"
  type        = string
  default     = "HARVESTLINK"
}
