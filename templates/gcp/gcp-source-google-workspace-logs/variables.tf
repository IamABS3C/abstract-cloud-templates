variable "log_project" {
  description = "Project that owns the connector service account. Can be the same one used for the Pub/Sub pipeline. Find it with: gcloud projects list"
  type        = string
}

variable "workspace_admin_email" {
  description = "A Workspace ADMIN the service account impersonates. Delegation acts as a real user — without a subject the Reports API returns 401, not an empty result. A Google Workspace SUPER ADMIN, used only for domain-wide delegation. No gcloud command lists this — ask whoever administers Workspace."
  type        = string
}

variable "workspace_app_groups" {
  description = "identity | admin | data | endpoint | collaboration | platform. Individual application names also work."
  type        = list(string)
  default     = ["identity", "admin"]
}

variable "workspace_applications" {
  type    = list(string)
  default = []
}

variable "workspace_service_account_id" {
  type    = string
  default = "abstract-workspace-reader"
}

variable "acknowledge_high_volume" {
  description = "Required to include gmail or drive."
  type        = bool
  default     = false
}

variable "include_directory_enrichment_scopes" {
  description = "Also print the Admin SDK Directory API scopes (admin.directory.user.readonly, admin.directory.group.readonly) in the delegation step. Abstract's Google Workspace integration does not request these scopes today, so leave this false unless another consumer needs them."
  type        = bool
  default     = false
}
