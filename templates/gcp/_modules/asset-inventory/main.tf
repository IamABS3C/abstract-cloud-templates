# ---------------------------------------------------------------------------
# Cloud Asset Inventory organization feed.
#
# ANOTHER thing the Log Router cannot carry. CAI publishes real-time resource
# and IAM-policy CHANGE notifications straight to Pub/Sub through its own feed —
# not a sink, not a filter.
#
# Why it earns its own deployment rather than being a catalog entry:
#
#   admin_activity tells you WHO CALLED WHAT API.
#   CAI tells you WHAT THE RESOURCE OR POLICY NOW IS, with the prior state.
#
# Those are different signals. An IAM binding added through three different
# paths produces three different audit entries and ONE identical policy diff —
# and the diff is what a detection actually wants. It is also the natural feed
# for an asset and identity model, because it carries inventory rather than
# just events.
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
  }
}

resource "google_pubsub_topic" "assets" {
  project = var.log_project
  name    = var.topic_name
  labels  = var.labels

  lifecycle { prevent_destroy = true }
}

resource "google_pubsub_subscription" "assets" {
  project                    = var.log_project
  name                       = var.subscription_name
  topic                      = google_pubsub_topic.assets.id
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = "${var.retention_days * 24 * 60 * 60}s"
  expiration_policy { ttl = "" }
  labels = var.labels

  lifecycle { prevent_destroy = true }
}

# The CAI service agent publishes, not you. Same shape as the Log Router writer
# identity and the GCS service agent: without this the feed is created
# successfully and delivers nothing.
#
# It is the agent of the feed's BILLING project (service-<project number>@gcp-sa-cloudasset),
# even for an organization feed; there is no organization-level CAI agent. It may not exist
# until something asks for it, so it is created here rather than assumed.
resource "google_project_service_identity" "cai" {
  provider = google-beta
  project  = var.log_project
  service  = "cloudasset.googleapis.com"
}

resource "google_pubsub_topic_iam_member" "cai_publisher" {
  project = var.log_project
  topic   = google_pubsub_topic.assets.id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_project_service_identity.cai.email}"
}

resource "google_cloud_asset_organization_feed" "abstract" {
  org_id          = var.org_id
  feed_id         = var.feed_id
  billing_project = var.log_project
  content_type    = var.content_type
  asset_types     = var.asset_types

  feed_output_config {
    pubsub_destination {
      topic = google_pubsub_topic.assets.id
    }
  }

  depends_on = [google_pubsub_topic_iam_member.cai_publisher]
}

resource "google_pubsub_subscription_iam_member" "abstract" {
  project      = var.log_project
  subscription = google_pubsub_subscription.assets.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.subscriber_service_account_email}"
}

resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = var.org_id != ""
      error_message = "org_id is required — the feed is organization-scoped, and its service agent identity is derived from it."
    }
    precondition {
      condition     = var.subscriber_service_account_email != ""
      error_message = "subscriber_service_account_email is required. Pass the identity 02-audit-logs-organization created, so ONE service account reads every feed rather than several to rotate."
    }
    precondition {
      condition     = length(var.asset_types) > 0 || var.acknowledge_all_asset_types
      error_message = "An empty asset_types feeds EVERY asset type in the organization — on a large estate that is a very large stream, and most of it is not security signal.\nStart with IAM policies and the resource types you actually detect on. To take everything deliberately, set acknowledge_all_asset_types = true."
    }
    precondition {
      condition     = contains(["RESOURCE", "IAM_POLICY", "ORG_POLICY", "ACCESS_POLICY", "OS_INVENTORY", "RELATIONSHIP"], var.content_type)
      error_message = "content_type must be one of RESOURCE, IAM_POLICY, ORG_POLICY, ACCESS_POLICY, OS_INVENTORY, RELATIONSHIP.\nIAM_POLICY is the highest-value one for security: it carries the policy diff, which admin_activity does not."
    }
  }
}
