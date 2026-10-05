# Cloud Asset Inventory — resource and IAM-policy CHANGES, org-wide.
#
# The third thing a log sink cannot carry. CAI has its own feed straight to
# Pub/Sub: not a sink, not a filter, and no widening of log_categories reaches it.
#
# Worth deploying alongside 02-audit-logs-organization rather than instead of it. They
# answer different questions:
#
#   admin_activity  who called which API
#   CAI IAM_POLICY  what the policy now IS, and what it was before
#
# Three different API paths to the same binding produce three audit entries and
# ONE identical policy diff. The diff is what a detection wants.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.0" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.0" }
  }
}

# The Cloud Asset API refuses user credentials without a quota project, so every read of
# the feed after it is created (plan, refresh, destroy) fails with 403 unless requests are
# billed to the logging project.
provider "google" {
  project               = var.log_project
  billing_project       = var.log_project
  user_project_override = true
}

provider "google-beta" {
  project               = var.log_project
  billing_project       = var.log_project
  user_project_override = true
}

module "asset_inventory" {
  source = "../_modules/asset-inventory"

  org_id                           = var.org_id
  log_project                      = var.log_project
  subscriber_service_account_email = local.subscriber_email
  content_type                     = var.content_type
  asset_types                      = var.asset_types
  acknowledge_all_asset_types      = var.acknowledge_all_asset_types
  retention_days                   = var.retention_days
  labels                           = var.labels
}
