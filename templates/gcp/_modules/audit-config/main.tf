# ---------------------------------------------------------------------------
# Data Access audit logs.
#
# SEPARATE ROOT MODULE ON PURPOSE — two independent reasons, either sufficient:
#
#   1. DESTROY BLAST RADIUS. If this lived with the log-export pipeline, a
#      `terraform destroy` of the collector would ALSO strip Data Access audit
#      logging across the organization. Tearing down a collector must never be
#      able to disable an organization's audit logging.
#
#   2. AUTHORITATIVE RESOURCE. google_*_iam_audit_config is authoritative for
#      the services it names and will fight anything else managing that IAM
#      policy. Keeping it in its own state makes the conflict visible instead
#      of intermittent.
#
# Admin Activity is ALWAYS ON and cannot be disabled — there is nothing to
# enable and nothing here can turn it off. Only Data Access is off by default,
# which is why this module exists at all.
#
# Inheritance is ONE-WAY: a project can ADD Data Access logging but cannot
# disable what an organization enabled. Scope deliberately.
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
  # ADMIN_WRITE is deliberately absent: that IS Admin Activity, always on.
  log_types = var.log_types

  services = length(var.services) > 0 ? var.services : ["allServices"]

  # service => log types, so one map drives all three scopes.
  service_config = {
    for s in local.services : s => local.log_types
  }
}

resource "google_organization_iam_audit_config" "this" {
  for_each = var.scope == "organization" ? local.service_config : {}
  org_id   = var.org_id
  service  = each.key

  dynamic "audit_log_config" {
    for_each = each.value
    content {
      log_type         = audit_log_config.value
      exempted_members = var.exempted_members
    }
  }
}

resource "google_folder_iam_audit_config" "this" {
  for_each = var.scope == "folder" ? local.service_config : {}
  folder   = var.folder_id
  service  = each.key

  dynamic "audit_log_config" {
    for_each = each.value
    content {
      log_type         = audit_log_config.value
      exempted_members = var.exempted_members
    }
  }
}

resource "google_project_iam_audit_config" "this" {
  for_each = var.scope == "project" ? local.service_config : {}
  project  = var.project_id
  service  = each.key

  dynamic "audit_log_config" {
    for_each = each.value
    content {
      log_type         = audit_log_config.value
      exempted_members = var.exempted_members
    }
  }
}

resource "terraform_data" "guards" {
  lifecycle {
    precondition {
      condition     = contains(["organization", "folder", "project"], var.scope)
      error_message = "scope must be organization, folder or project."
    }
    precondition {
      condition     = var.scope != "organization" || var.org_id != ""
      error_message = "scope = organization requires org_id."
    }
    precondition {
      condition     = var.scope != "folder" || var.folder_id != ""
      error_message = "scope = folder requires folder_id."
    }
    precondition {
      condition     = var.scope != "project" || var.project_id != ""
      error_message = "scope = project requires project_id."
    }
    # google_*_iam_audit_config is AUTHORITATIVE PER SERVICE. If the org already
    # has an allServices config with DATA_READ — set by a platform team, a CIS
    # benchmark, or a landing zone — applying a narrower set here REMOVES it.
    #
    # A security tool silently switching off audit logging is the worst failure
    # this repo could have, and it would be loud in neither the plan summary nor
    # the docs. So targeting allServices requires saying so out loud.
    precondition {
      condition     = !contains(local.services, "allServices") || var.acknowledge_authoritative_overwrite
      error_message = "services resolves to `allServices`, and google_*_iam_audit_config is AUTHORITATIVE for the service it names.\nIf this scope ALREADY has an allServices audit config with log types you are not listing, THIS APPLY REMOVES THEM.\n\nRun `scripts/preflight.sh` first and read the 'Data Access audit logging' section — it prints what is enabled today.\nThen either list every log type you intend to keep, target named services instead, or set acknowledge_authoritative_overwrite = true."
    }
    precondition {
      condition     = !contains(local.log_types, "ADMIN_WRITE")
      error_message = "ADMIN_WRITE is Admin Activity — always on, cannot be disabled, and not something this module should claim to manage. Remove it."
    }
    precondition {
      condition     = var.acknowledge_data_read || !contains(local.log_types, "DATA_READ") || length(var.services) > 0
      error_message = "DATA_READ on allServices routes every read in the organization.\nOn a BigQuery-heavy estate that moves total volume by one to two orders of magnitude.\nScope it via `services`, or set acknowledge_data_read = true."
    }
  }
}
