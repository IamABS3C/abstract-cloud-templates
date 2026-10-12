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
# enable and nothing here can turn it off. Data Access is off by default for every
# service except BigQuery (which writes its Data Access logs by default), which is
# why this module exists at all.
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
    # google_*_iam_audit_config is AUTHORITATIVE PER SERVICE, for every service it names, not only
    # allServices. If a service already has DATA_READ, or exempted members, set by a platform team, a CIS
    # benchmark or a landing zone, applying a narrower set here REMOVES them; and destroy removes the
    # whole config, including what existed before. The plan shows only a create.
    #
    # A security tool silently switching off audit logging is the worst failure this repo could have,
    # and it would be loud in neither the plan summary nor the docs. So applying requires saying so.
    # (No prevent_destroy on the configs: removing one service from `services` is a destroy of that
    # service's config, and turning logging off on purpose must stay possible without editing code.)
    precondition {
      condition     = var.acknowledge_authoritative_overwrite
      error_message = "google_*_iam_audit_config is AUTHORITATIVE for each service it names, and this module applies ONE log_types list and ONE exempted_members list to every service it names:\n  ${join(", ", local.services)}\nTHIS APPLY REPLACES every Data Access log type and exempted member already set on those services at this scope with those two lists, and `terraform destroy` REMOVES them, including settings that predate this template.\n\nRun tools/gcp-guided-setup/preflight.sh first and read its 'Data Access audit logging' section: it marks each service whose settings today differ from what this template sets. Name only services whose existing settings you accept being replaced by these lists. Leave out of services any service that already has DATA_READ or exempted members, or manage it only from a separate root with its own backend prefix, after removing it from this root's services: copying them into log_types or exempted_members applies them to every named service. Then set acknowledge_authoritative_overwrite = true.\nTo stop managing these settings without changing them (offboarding), run: terraform state rm 'module.audit_config'. Use terraform destroy only to turn this logging off on purpose."
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
