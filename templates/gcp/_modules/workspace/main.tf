# ---------------------------------------------------------------------------
# Google Workspace / Cloud Identity audit logs.
#
# THIS IS A DIFFERENT PIPELINE. Abstract reads Workspace audit data from the
# Admin SDK **Reports API**, not from Cloud Logging, through a separate
# integration (default.google_workspace, PULL) with its own auth model. No sink
# or topic is involved.
#
# Workspace can also share a subset of its audit logs with Google Cloud
# (admin.google.com > Account settings > Legal and compliance > Sharing options).
# Shared logs land in Cloud Logging at the organization level, where an
# organization sink can route them. That is optional, covers fewer services than
# the Reports API, and this module neither needs nor configures it.
#
# The trap this exists to close: a customer asking for "GCP identity logs"
# usually means Workspace sign-ins. GCP console and gcloud logins DO appear in
# admin_activity; Workspace user auth does not. Get that settled on the first
# call, or you deliver a perfect Pub/Sub pipeline that still cannot say who
# logged in.
#
# What Terraform can and cannot do here:
#   CAN  create the service account, enable the API, and emit the exact
#        client ID + scopes + Abstract field values you need
#   CANNOT grant domain-wide delegation. That is a Workspace SUPER ADMIN
#        action in admin.google.com, and there is no API or provider for it.
#        The outputs below give the operator the precise values to paste.
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
  # Verified against Google's OAuth 2.0 scope registry 2026-08-26.
  workspace_base_scopes = [
    "https://www.googleapis.com/auth/admin.reports.audit.readonly",
    "https://www.googleapis.com/auth/admin.reports.usage.readonly",
  ]
  # Printed only when include_directory_enrichment_scopes = true. Abstract's
  # Google Workspace integration does not request these today.
  workspace_directory_scopes = [
    "https://www.googleapis.com/auth/admin.directory.user.readonly",
    "https://www.googleapis.com/auth/admin.directory.group.readonly",
  ]
  workspace_scopes = var.include_directory_enrichment_scopes ? concat(local.workspace_base_scopes, local.workspace_directory_scopes) : local.workspace_base_scopes

  # The 23 applications the integration accepts, grouped by what they answer.
  # Verified live against default.google_workspace.0_1_0.
  workspace_app_groups = {
    identity      = ["login", "saml", "token", "user_accounts", "context_aware_access"]
    admin         = ["admin", "groups", "groups_enterprise", "rules"]
    data          = ["drive", "gmail", "calendar", "keep", "vault"]
    endpoint      = ["chrome", "mobile"]
    collaboration = ["chat", "meet", "jamboard", "gplus"]
    platform      = ["access_transparency", "gcp", "data_studio"]
  }

  workspace_expanded = distinct(flatten([
    for g in var.workspace_app_groups : lookup(local.workspace_app_groups, g, [g])
  ]))

  workspace_apps = length(var.workspace_applications) > 0 ? var.workspace_applications : local.workspace_expanded

  workspace_unknown_groups = [
    for g in var.workspace_app_groups : g
    if !contains(keys(local.workspace_app_groups), g) && !contains(flatten(values(local.workspace_app_groups)), g)
  ]
}

resource "google_project_service" "admin_sdk" {
  count              = var.enable_workspace ? 1 : 0
  project            = var.log_project
  service            = "admin.googleapis.com"
  disable_on_destroy = false
}

# A DEDICATED service account. Do not reuse the Pub/Sub one: this identity is
# granted domain-wide delegation over Workspace, which is a far broader trust
# than reading one subscription, and the two should be revocable separately.
resource "google_service_account" "workspace" {
  count        = var.enable_workspace ? 1 : 0
  project      = var.log_project
  account_id   = var.workspace_service_account_id
  display_name = "Abstract Security — Google Workspace Reports API"
  description  = "Domain-wide delegated. Reads Admin SDK Reports API audit activity. Grants NO Google Cloud permissions."
}

resource "terraform_data" "validate_workspace" {
  count = var.enable_workspace ? 1 : 0
  lifecycle {
    precondition {
      condition     = length(local.workspace_unknown_groups) == 0
      error_message = "Unknown workspace_app_groups: ${join(", ", local.workspace_unknown_groups)}.\nValid groups: identity, admin, data, endpoint, collaboration, platform.\nOr name individual applications in workspace_applications."
    }
    precondition {
      condition     = var.workspace_admin_email != ""
      error_message = "enable_workspace requires workspace_admin_email — the Workspace admin the service account impersonates.\nDomain-wide delegation acts AS a real user; without a subject the Reports API returns 401."
    }
    precondition {
      condition     = var.acknowledge_high_volume || length(setintersection(toset(local.workspace_apps), toset(["gmail", "drive"]))) == 0
      error_message = "gmail and drive are the volume monsters in Workspace audit — on a large tenant they dwarf every other application combined.\nStart with identity + admin, measure, then add. To proceed set acknowledge_high_volume = true."
    }
  }
}
