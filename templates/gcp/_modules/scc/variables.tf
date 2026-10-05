variable "enable_scc_findings" {
  description = <<-EOT
    Collect Security Command Center findings. SCC does NOT flow through the Log Router --
    it publishes to Pub/Sub through its own NotificationConfig, so no log filter can ever
    collect it. Creates a separate topic and subscription, because findings are a
    different shape from audit logs.

    Requires SCC Premium or Enterprise, and roles/securitycenter.notificationConfigEditor
    at the organization.
  EOT
  type        = bool
  default     = false
}
variable "scc_config_id" {
  description = "SCC NotificationConfig ID. Lowercase letters, numbers and hyphens."
  type        = string
  default     = "abstract-findings"
}
variable "scc_filter" {
  description = "SCC streaming filter. Default is active findings only -- muted and resolved findings are noise in a SIEM."
  type        = string
  default     = "state=\"ACTIVE\" AND NOT mute=\"MUTED\""
}

variable "log_project" {
  type = string
}

variable "org_id" {
  type    = string
  default = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "topic_name" {
  type    = string
  default = "abstract-audit-logs"
}

variable "subscription_name" {
  type    = string
  default = "abstract-audit-logs-sub"
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "ack_deadline_seconds" {
  type    = number
  default = 60
}

variable "subscriber_service_account_email" {
  description = "Abstract's service account, created by the log-export module. Passed in rather than created again so both feeds are read by ONE identity."
  type        = string
}
