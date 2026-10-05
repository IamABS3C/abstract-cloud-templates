variable "enable_workspace" {
  description = <<-EOT
    Set up the Google Workspace audit-log integration. This is a SEPARATE pipeline from
    the log sink -- Abstract reads Workspace audit data from the Admin SDK Reports API,
    not from Cloud Logging.

    Workspace can also share a subset of its audit logs with Google Cloud (admin.google.com
    -> Account settings -> Legal and compliance -> Sharing options). Those land in Cloud
    Logging at the organization level, where an organization sink can route them. That path
    is optional and covers fewer services than the Reports API; it does not replace this one.

    Creates a dedicated service account and emits the exact client ID, scopes and Abstract
    field values. Domain-wide delegation itself must be granted by a Workspace SUPER ADMIN
    in admin.google.com -- there is no API for it.
  EOT
  type        = bool
  default     = false
}
variable "workspace_admin_email" {
  description = "A Google Workspace ADMIN user the service account impersonates. Domain-wide delegation acts as a real user; without a subject the Reports API returns 401. Goes into Abstract's Admin Email field."
  type        = string
  default     = ""
}
variable "workspace_service_account_id" {
  description = "Account ID for the Workspace connector service account. Deliberately separate from the Pub/Sub one -- domain-wide delegation is a much broader trust and should be revocable on its own."
  type        = string
  default     = "abstract-workspace-reader"
}
variable "workspace_app_groups" {
  description = <<-EOT
    Which Workspace applications to collect, by group. Individual application names also
    work here.

      identity      login, saml, token, user_accounts, context_aware_access
                    -- the answer to "who signed in", and what most customers actually mean
      admin         admin, groups, groups_enterprise, rules
      data          drive, gmail, calendar, keep, vault  -- gmail and drive are the volume monsters
      endpoint      chrome, mobile
      collaboration chat, meet, jamboard, gplus
      platform      access_transparency, gcp, data_studio

    Default is identity + admin: the high-signal control-plane set.
  EOT
  type        = list(string)
  default     = ["identity", "admin"]
}
variable "workspace_applications" {
  description = "Explicit application list, overriding workspace_app_groups. Valid: access_transparency, admin, calendar, chat, chrome, context_aware_access, data_studio, drive, gcp, gmail, gplus, groups, groups_enterprise, jamboard, keep, login, meet, mobile, rules, saml, token, user_accounts, vault"
  type        = list(string)
  default     = []
}

variable "log_project" {
  description = "Project owning the connector service account and the Admin SDK API enablement."
  type        = string
}

variable "acknowledge_high_volume" {
  description = "Required to include gmail or drive — on a large tenant they dwarf every other application combined."
  type        = bool
  default     = false
}

variable "include_directory_enrichment_scopes" {
  description = "Also print the Admin SDK Directory API scopes (admin.directory.user.readonly, admin.directory.group.readonly) in the delegation step. Abstract's Google Workspace integration does not request these scopes today, so leave this false unless another consumer needs them: delegating them grants read access to every user and group record."
  type        = bool
  default     = false
}
