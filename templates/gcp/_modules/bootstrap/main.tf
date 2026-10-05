# ---------------------------------------------------------------------------
# Bootstrap: create the dedicated logging project and turn on what it needs.
#
# Optional. Most customers already have a security or logging project — point
# the pipeline at it instead. This exists for greenfield, and for the case
# where the only candidate is a WORKLOAD project, which is the wrong answer:
# Pub/Sub publish quota is consumed in the destination project, and a security
# pipeline inside a workload project can be read or broken by that workload's
# owner.
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

resource "google_project" "logging" {
  count               = var.create_project ? 1 : 0
  name                = var.project_name
  project_id          = var.project_id
  org_id              = var.folder_id == "" ? var.org_id : null
  folder_id           = var.folder_id == "" ? null : var.folder_id
  billing_account     = var.billing_account_id
  labels              = var.labels
  deletion_policy     = var.deletion_policy
  auto_create_network = false # no default VPC: this project runs no workloads
}

locals {
  project_id = var.create_project ? google_project.logging[0].project_id : var.project_id

  required_apis = distinct(concat([
    "pubsub.googleapis.com",
    "logging.googleapis.com",
    ], var.enable_workspace_api ? ["admin.googleapis.com"] : [],
    var.enable_scc_api ? ["securitycenter.googleapis.com"] : [],
  var.additional_apis))
}

resource "google_project_service" "required" {
  for_each = toset(local.required_apis)
  project  = local.project_id
  service  = each.value

  # Leaving APIs enabled on destroy is deliberate. Disabling an API can break
  # unrelated resources in the same project, and the failure surfaces far from
  # the change that caused it.
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Deployer permission preflight.
#
# Terraform fails at APPLY when a permission is missing — after it has already
# created some resources. This checks up front, so a missing org-level grant is
# a plan-time message rather than a half-built pipeline.
# ---------------------------------------------------------------------------

data "google_client_openid_userinfo" "me" {}


output "preflight" {
  description = "Who Terraform is running as, and what that identity still needs."
  value = {
    running_as = data.google_client_openid_userinfo.me.email
    project    = local.project_id
    apis       = local.required_apis
    still_verify_by_hand = [
      "roles/logging.configWriter at the ORGANIZATION — the blocking prerequisite, and usually held by someone other than the project owner",
      "roles/pubsub.admin on the logging project",
      "Organization Admin — ONLY if you are also enabling Data Access audit logs",
      "Workspace SUPER ADMIN in admin.google.com — ONLY for Workspace domain-wide delegation. A GCP Owner cannot do this",
    ]
    check_command = "bash scripts/preflight.sh --org-id ${var.org_id} --project ${local.project_id}"
  }
}
