# ---------------------------------------------------------------------------
# Logs that are ALREADY sitting in a Cloud Storage bucket.
#
# A different problem from the Log Router, and a different mechanism. When a
# vendor, an existing export, or a third-party appliance already writes objects
# into a bucket, you do not want a log sink — you want GCS object notifications:
#
#   bucket → OBJECT_FINALIZE notification → Pub/Sub → Abstract pulls → fetches
#
# THE NOTIFICATION IS A POINTER, NOT THE DATA. That single fact drives every
# permission below and is the most-missed thing on this path: Abstract needs to
# read the SUBSCRIPTION *and* the OBJECT, on two different services.
#
# One genuine advantage over the AWS equivalent: adding a GCS notification
# config ADDS to the bucket's existing configs. AWS's
# PutBucketNotificationConfiguration REPLACES the whole document and has
# silently destroyed other consumers' wiring. Still list existing configs first.
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

locals {
  # bucket => owning project. `buckets` (list) + `bucket_project` (scalar) is kept
  # working as a shim, but a list of buckets across DIFFERENT projects silently
  # broke: each project has its OWN GCS service agent, and only one was ever
  # granted publisher. The unlucky buckets got a notification config that created
  # successfully and delivered nothing, forever -- the exact silent failure this
  # module exists to prevent, reproduced inside it.
  bucket_projects = length(var.bucket_map) > 0 ? var.bucket_map : {
    for b in var.buckets : b => var.bucket_project
  }
  distinct_projects = distinct(values(local.bucket_projects))
}

# One service agent per distinct owning project.
data "google_storage_project_service_account" "gcs" {
  for_each = toset(local.distinct_projects)
  project  = each.value
}

resource "google_pubsub_topic" "notifications" {
  project = var.log_project
  name    = var.topic_name
  labels  = var.labels
}

resource "google_pubsub_subscription" "notifications" {
  project                    = var.log_project
  name                       = var.subscription_name
  topic                      = google_pubsub_topic.notifications.id
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = "${var.retention_days * 24 * 60 * 60}s"

  # Empty ttl = never expire. The default DELETES the subscription after 31
  # days idle, which silently kills a low-traffic feed a month in.
  expiration_policy { ttl = "" }
  labels = var.labels
}

# ---------------------------------------------------------------------------
# 1. The GCS SERVICE AGENT publishes — not you, and not Abstract.
#    Skipping this produces a notification config that is created successfully
#    and delivers nothing, forever. Same shape as the Log Router writer
#    identity, and just as silent.
# ---------------------------------------------------------------------------
resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  for_each = data.google_storage_project_service_account.gcs

  project = var.log_project
  topic   = google_pubsub_topic.notifications.id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${each.value.email_address}"
}

# ---------------------------------------------------------------------------
# 2. The notification config itself.
#
#    depends_on is REQUIRED, not defensive: google_storage_notification
#    validates at create time that GCS can publish to the topic. Without the
#    dependency a fresh apply races the IAM binding and fails.
# ---------------------------------------------------------------------------
resource "google_storage_notification" "abstract" {
  for_each = local.bucket_projects

  bucket             = each.key
  topic              = google_pubsub_topic.notifications.id
  payload_format     = "JSON_API_V1"
  event_types        = var.event_types
  object_name_prefix = var.object_name_prefix

  depends_on = [google_pubsub_topic_iam_member.gcs_publisher]
}

# ---------------------------------------------------------------------------
# 3. Abstract's identity — TWO grants on TWO services.
#    subscriber on the subscription reads the pointer.
#    objectViewer on the bucket reads the object the pointer points at.
#    Missing the second gives you notifications with no content, which reads
#    like a parser problem and is not one.
# ---------------------------------------------------------------------------
resource "google_service_account" "abstract" {
  count        = var.create_service_account ? 1 : 0
  project      = var.log_project
  account_id   = var.service_account_id
  display_name = "Abstract Security — GCS object log reader"
}

locals {
  sa_email = var.create_service_account ? google_service_account.abstract[0].email : var.existing_service_account_email
}

resource "google_pubsub_subscription_iam_member" "abstract" {
  project      = var.log_project
  subscription = google_pubsub_subscription.notifications.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${local.sa_email}"
}

# Scoped to the prefix when one is set. Granting bucket-wide objectViewer while
# the notification config is prefix-scoped means Abstract can read every object
# in a bucket it was only ever meant to read one prefix of -- a quiet
# over-grant that nobody notices because the pipeline works either way.
resource "google_storage_bucket_iam_member" "abstract_object_reader" {
  for_each = local.bucket_projects
  bucket   = each.key
  role     = "roles/storage.objectViewer"
  member   = "serviceAccount:${local.sa_email}"

  dynamic "condition" {
    for_each = var.object_name_prefix == "" ? [] : [1]
    content {
      title       = "prefix-scoped"
      description = "Read only objects under ${var.object_name_prefix}, matching the notification config."
      expression  = "resource.name.startsWith(\"projects/_/buckets/${each.key}/objects/${var.object_name_prefix}\")"
    }
  }
}

# On a CMEK bucket every fetch fails with an error that blames Storage rather
# than KMS, which sends people down the wrong path entirely.
resource "google_kms_crypto_key_iam_member" "abstract_decrypter" {
  count         = var.cmek_crypto_key_id == "" ? 0 : 1
  crypto_key_id = var.cmek_crypto_key_id
  role          = "roles/cloudkms.cryptoKeyDecrypter"
  member        = "serviceAccount:${local.sa_email}"
}

resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = length(local.bucket_projects) > 0
      error_message = "buckets must name at least one bucket. There is no org-level equivalent of a notification config — each bucket is wired individually."
    }
    precondition {
      condition     = var.create_service_account || var.existing_service_account_email != ""
      error_message = "Set create_service_account = true, or pass existing_service_account_email to reuse the identity the log-export module created."
    }
    precondition {
      condition     = !contains(var.event_types, "OBJECT_DELETE") || var.acknowledge_delete_events
      error_message = "OBJECT_DELETE notifications describe objects that no longer exist, so the fetch that follows will 404.\nUseful only if you are watching for deletions as a signal in itself. Set acknowledge_delete_events = true."
    }
    precondition {
      condition     = length(local.bucket_projects) <= 10 || var.acknowledge_bucket_sprawl
      error_message = "${length(local.bucket_projects)} buckets wired individually. A notification config binds to ONE bucket with no inheritance, so an estate that keeps creating log buckets has an architecture problem an aggregated sink would solve.\nIf these really are third-party exports you do not control, set acknowledge_bucket_sprawl = true."
    }
  }
}
