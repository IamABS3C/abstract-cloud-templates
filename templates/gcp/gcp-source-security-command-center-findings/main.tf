# Security Command Center findings.
#
# SCC does NOT flow through the Log Router. It publishes to Pub/Sub through its
# own NotificationConfig — not a sink, not a filter. No log_categories entry and
# no widened filter will ever collect it, which is why this is its own
# deployment rather than a flag on the log export.
#
# Its own topic and subscription on purpose: findings are a different shape from
# audit logs, arrive at a different rate, and you may want different retention.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.log_project
}

module "scc" {
  source = "../_modules/scc"

  enable_scc_findings              = true
  org_id                           = var.org_id
  log_project                      = var.log_project
  scc_config_id                    = var.scc_config_id
  scc_filter                       = var.scc_filter
  subscriber_service_account_email = local.subscriber_email
  retention_days                   = var.retention_days
  labels                           = var.labels
}
