# Data Access audit logs — SEPARATE STATE ON PURPOSE.
#
# Kept apart from the log-export pipeline for two independent reasons, either
# sufficient on its own:
#
#   1. A `terraform destroy` of the collector must never be able to strip an
#      organization's Data Access audit logging. Separate state makes that
#      impossible rather than merely unlikely.
#
#   2. google_*_iam_audit_config is AUTHORITATIVE for the services it names and
#      will fight anything else managing that IAM policy — an ALZ-style org
#      policy pipeline, for instance. Isolated state makes the conflict
#      visible instead of intermittent.
#
# Admin Activity is ALWAYS ON and cannot be disabled. Nothing here enables it,
# and nothing here can turn it off. Only Data Access is off by default.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

module "audit_config" {
  source = "../_modules/audit-config"

  scope                               = var.scope
  org_id                              = var.org_id
  folder_id                           = var.folder_id
  project_id                          = var.project_id
  log_types                           = var.log_types
  services                            = var.services
  exempted_members                    = var.exempted_members
  acknowledge_data_read               = var.acknowledge_data_read
  acknowledge_authoritative_overwrite = var.acknowledge_authoritative_overwrite
}
