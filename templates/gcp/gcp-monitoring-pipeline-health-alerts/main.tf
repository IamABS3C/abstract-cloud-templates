# Alerting on the pipeline itself.
#
# Deploy this WITH 02-audit-logs-organization, not after. Every other deployment in this
# repo documents a silent failure; this is the one that catches them. Docs
# without alerting create confidence the runtime has not earned.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.log_project
}

module "monitoring" {
  source = "../_modules/monitoring"

  log_project                   = var.log_project
  topic_id                      = var.topic_id
  subscription_id               = var.subscription_id
  dead_letter_topic_id          = var.dead_letter_topic_id
  notification_channels         = var.notification_channels
  acknowledge_no_channel        = var.acknowledge_no_channel
  retention_days                = var.retention_days
  unacked_age_threshold_seconds = var.unacked_age_threshold_seconds
  absence_threshold_seconds     = var.absence_threshold_seconds
  prefix                        = var.prefix
}
