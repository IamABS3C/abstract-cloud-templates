# Logs ALREADY sitting in a Cloud Storage bucket.
#
# For vendor exports, third-party appliances, or an existing pipeline that
# writes objects. Different mechanism from the Log Router entirely:
#
#   bucket → OBJECT_FINALIZE notification → Pub/Sub → Abstract fetches the object
#
# If the logs are Google's own, use 02-audit-logs-organization instead. An aggregated sink
# is strictly better than watching buckets.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.log_project
}

module "gcs_notifications" {
  source = "../_modules/gcs-notifications"

  buckets                        = var.buckets
  bucket_map                     = var.bucket_map
  bucket_project                 = var.bucket_project
  log_project                    = var.log_project
  object_name_prefix             = var.object_name_prefix
  cmek_crypto_key_id             = var.cmek_crypto_key_id
  create_service_account         = var.existing_service_account_email == ""
  existing_service_account_email = var.existing_service_account_email
  acknowledge_bucket_sprawl      = var.acknowledge_bucket_sprawl
  labels                         = var.labels
}
