# Cold archive and replay.
#
# A SECOND sink writing to Cloud Storage. A sink has exactly one destination, so
# this cannot be an extra destination on the streaming sink — it is its own.
#
# NOT the detection path. GCS batches, so latency becomes minutes to hours.
# Reserve it for archive, evidence and backfill; keep the Pub/Sub sink for
# anything you alert on.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.log_project
}

module "archive" {
  source = "../_modules/archive"

  enable_gcs_archive          = true
  org_id                      = var.org_id
  log_project                 = var.log_project
  sink_scope                  = "organization"
  sink_name                   = var.sink_name
  filter                      = local.archive_filter
  archive_bucket_name         = var.archive_bucket_name
  archive_bucket_location     = var.archive_bucket_location
  archive_retention_days      = var.archive_retention_days
  archive_retention_locked    = var.archive_retention_locked
  archive_versioning          = var.archive_versioning
  archive_cmek_key            = var.archive_cmek_key
  archive_nearline_after_days = var.archive_nearline_after_days
  labels                      = var.labels
}
