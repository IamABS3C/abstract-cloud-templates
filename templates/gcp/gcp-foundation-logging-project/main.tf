# Create the dedicated logging project and enable what the pipeline needs.
#
# OPTIONAL. Most customers already have a security or logging project — point
# 02-audit-logs-organization at it and skip this entirely. Run this for greenfield, or when
# the only candidate is a WORKLOAD project, which is the wrong answer: Pub/Sub
# publish quota is consumed in the destination project, and a security pipeline
# inside a workload project can be read or broken by that workload's owner.

terraform {
  required_version = ">= 1.5"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 6.0" }
  }
}

provider "google" {}

module "bootstrap" {
  source = "../_modules/bootstrap"

  create_project       = var.create_project
  project_id           = var.project_id
  project_name         = var.project_name
  org_id               = var.org_id
  folder_id            = var.folder_id
  billing_account_id   = var.billing_account_id
  enable_workspace_api = var.enable_workspace_api
  enable_scc_api       = var.enable_scc_api
  labels               = var.labels
}
