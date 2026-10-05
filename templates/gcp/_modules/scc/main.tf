# ---------------------------------------------------------------------------
# Security Command Center findings.
#
# SCC does NOT flow through the Log Router. It has its own NotificationConfig
# that publishes findings straight to a Pub/Sub topic — not a sink, not a
# filter. So no log_categories entry can ever collect it, and a customer who
# asks for "SCC in Abstract" is asking for this resource, not a wider filter.
#
# It publishes to its OWN topic by default so SCC findings and audit logs stay
# separable: they are different shapes and you may want different retention.
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

resource "google_pubsub_topic" "scc" {
  count   = var.enable_scc_findings ? 1 : 0
  project = var.log_project
  name    = "${var.topic_name}-scc"
  labels  = var.labels
}

resource "google_pubsub_subscription" "scc" {
  count                      = var.enable_scc_findings ? 1 : 0
  project                    = var.log_project
  name                       = "${var.subscription_name}-scc"
  topic                      = google_pubsub_topic.scc[0].id
  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = "${var.retention_days * 24 * 60 * 60}s"
  expiration_policy { ttl = "" }
  labels = var.labels
}

resource "google_scc_v2_organization_notification_config" "abstract" {
  count        = var.enable_scc_findings ? 1 : 0
  config_id    = var.scc_config_id
  organization = var.org_id
  location     = "global"
  description  = "Security Command Center findings to Abstract Security"
  pubsub_topic = google_pubsub_topic.scc[0].id

  streaming_config {
    filter = var.scc_filter
  }
}

resource "google_pubsub_subscription_iam_member" "scc_subscriber" {
  count        = var.enable_scc_findings ? 1 : 0
  project      = var.log_project
  subscription = google_pubsub_subscription.scc[0].id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:${var.subscriber_service_account_email}"
}
