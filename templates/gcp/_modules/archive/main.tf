# ---------------------------------------------------------------------------
# Optional GCS archive destination.
#
# A SECOND sink to Cloud Storage, for cold storage and backfill. Deliberately a
# separate sink rather than a second destination on the first one: a sink has
# exactly one destination.
#
# This is NOT the streaming path. GCS batches, so detection latency becomes
# minutes to hours — reserve it for archive and replay, never as the primary.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

resource "google_storage_bucket" "archive" {
  count                       = var.enable_gcs_archive ? 1 : 0
  project                     = var.log_project
  name                        = var.archive_bucket_name
  location                    = var.archive_bucket_location
  uniform_bucket_level_access = true
  force_destroy               = false

  # Retention lock is what makes this an evidentiary archive rather than a copy.
  # A retention policy WITHOUT is_locked can be shortened or removed by anyone
  # with storage.buckets.update. That is a default, not immutability -- and it
  # must not be described as WORM, because a customer will put that in an audit
  # response. is_locked is separate, explicit, and defaults to false BECAUSE IT
  # IS IRREVERSIBLE: once locked, the policy cannot be shortened or removed for
  # the life of the bucket, by anyone, including Google support.
  dynamic "retention_policy" {
    for_each = var.archive_retention_days > 0 ? [1] : []
    content {
      retention_period = var.archive_retention_days * 24 * 60 * 60
      is_locked        = var.archive_retention_locked
    }
  }

  # An evidentiary bucket should never be publicly reachable, and should keep
  # superseded objects.
  public_access_prevention = "enforced"

  versioning {
    enabled = var.archive_versioning
  }

  dynamic "encryption" {
    for_each = var.archive_cmek_key == "" ? [] : [1]
    content {
      default_kms_key_name = var.archive_cmek_key
    }
  }

  lifecycle_rule {
    condition { age = var.archive_nearline_after_days }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }
  labels = var.labels
}

resource "google_logging_organization_sink" "archive" {
  count            = var.enable_gcs_archive && var.sink_scope == "organization" ? 1 : 0
  name             = "${var.sink_name}-archive"
  org_id           = var.org_id
  destination      = "storage.googleapis.com/${google_storage_bucket.archive[0].name}"
  include_children = true
  filter           = var.filter
}

resource "google_storage_bucket_iam_member" "archive_writer" {
  count  = var.enable_gcs_archive && var.sink_scope == "organization" ? 1 : 0
  bucket = google_storage_bucket.archive[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_organization_sink.archive[0].writer_identity
}
