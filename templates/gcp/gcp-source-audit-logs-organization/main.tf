# Organization-wide audit log export to Abstract Security.
# One aggregated sink. Every project, current and future, by containment.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {
  project = var.log_project
}

module "log_export" {
  source = "../_modules/log-export"

  sink_scope  = "organization"
  org_id      = var.org_id
  log_project = var.log_project

  log_categories                    = var.log_categories
  data_access_services              = var.data_access_services
  exclusions                        = var.exclusions
  acknowledge_high_volume           = var.acknowledge_high_volume
  labels                            = var.labels
  retention_days                    = var.retention_days
  ack_deadline_seconds              = var.ack_deadline_seconds
  enable_dead_letter                = var.enable_dead_letter
  dead_letter_max_delivery_attempts = var.dead_letter_max_delivery_attempts
  topic_name                        = var.topic_name
  subscription_name                 = var.subscription_name
  sink_name                         = var.sink_name
  service_account_id                = var.service_account_id
  custom_filter                     = var.custom_filter
  platform_log_filters              = var.platform_log_filters
}
