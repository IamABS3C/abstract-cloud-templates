variable "org_id" {
  description = "Organization ID the inventory feed binds to. Find it with: gcloud organizations list"
  type        = string
}
variable "log_project" {
  description = "DEDICATED logging or security project holding this pipeline. Not a workload project. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with deployments/01-logging-project (set create_project = true)."
  type        = string
}

variable "remote_state_bucket" {
  description = "GCS bucket holding 02-audit-logs-organization's state. Set this and Abstract's identity is READ rather than retyped. Empty falls back to subscriber_service_account_email."
  type        = string
  default     = ""
}

variable "remote_state_prefix" {
  description = "State key of 02-audit-logs-organization. It keeps that folder's original name, 01-organization, so existing state is found."
  type        = string
  default     = "01-organization"
}

variable "subscriber_service_account_email" {
  description = "Fallback when remote_state_bucket is empty. From 02-audit-logs-organization's abstract_onboarding output."
  type        = string
  default     = ""
}

variable "content_type" {
  description = "IAM_POLICY (default, highest security value) | RESOURCE | ORG_POLICY | ACCESS_POLICY | OS_INVENTORY | RELATIONSHIP"
  type        = string
  default     = "IAM_POLICY"
}

variable "asset_types" {
  description = "Asset types to watch. Empty means everything and requires acknowledge_all_asset_types."
  type        = list(string)
  default = [
    "cloudresourcemanager.googleapis.com/Project",
    "cloudresourcemanager.googleapis.com/Folder",
    "iam.googleapis.com/ServiceAccount",
    "iam.googleapis.com/ServiceAccountKey",
    "storage.googleapis.com/Bucket",
    "compute.googleapis.com/Firewall",
  ]
}

variable "acknowledge_all_asset_types" {
  type    = bool
  default = false
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "labels" {
  type    = map(string)
  default = {}
}
