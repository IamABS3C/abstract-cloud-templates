variable "org_id" {
  description = "Organization ID. SCC NotificationConfig is organization-scoped. Find it with: gcloud organizations list"
  type        = string
}

variable "log_project" {
  description = "Project holding the findings topic and subscription. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with deployments/01-logging-project (set create_project = true) — do not point this at a workload project."
  type        = string
}

variable "subscriber_service_account_email" {
  description = "Fallback when remote_state_bucket is empty. Abstract's identity from 02-audit-logs-organization — reusing it means ONE identity reads every feed instead of several to rotate."
  type        = string
  default     = ""
}

variable "scc_config_id" {
  type    = string
  default = "abstract-findings"
}

variable "scc_filter" {
  description = "SCC streaming filter. The default is active, unmuted findings — muted and resolved findings are noise in a SIEM, and they are the bulk of the volume on a mature SCC deployment."
  type        = string
  default     = "state=\"ACTIVE\" AND NOT mute=\"MUTED\""
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "remote_state_bucket" {
  description = "GCS bucket holding 02-audit-logs-organization's state. Set it and the value below is READ rather than retyped. Empty uses the literal."
  type        = string
  default     = ""
}

variable "remote_state_prefix" {
  description = "State key of 02-audit-logs-organization. It keeps that folder's original name, 01-organization, so existing state is found."
  type        = string
  default     = "01-organization"
}
