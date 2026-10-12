variable "org_id" {
  description = "Organization ID. Find it with: gcloud organizations list"
  type        = string
}

variable "log_project" {
  description = "DEDICATED logging or security project holding the topic and subscription. Not a workload project — Pub/Sub publish quota is consumed here, and a workload owner should not be able to read or break the security pipeline. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with templates/gcp/gcp-foundation-logging-project (set create_project = true) — do not point this at a workload project."
  type        = string
}

variable "log_categories" {
  description = "Named sources to route, from templates/gcp/_modules/log-export/log_catalog.tf. The default is the three Cloud Audit Logs Abstract's managed GCP Pub/Sub parser stores; it drops every record that is not a Cloud Audit Log, so use gcp-source-network-threat-logs for firewall, DNS and load-balancer logs. Add identity_access to route service account token minting (iamcredentials) and Workload Identity Federation (sts)."
  type        = list(string)
  default     = ["admin_activity", "system_event", "policy_denied"]
}

variable "data_access_services" {
  description = "Read only when data_access_all is in log_categories; on its own it routes nothing (for identity events add identity_access to log_categories). Use the serviceName the events carry: iamcredentials.googleapis.com for token minting, sts.googleapis.com for federation. Empty means every service."
  type        = list(string)
  default     = ["bigquery.googleapis.com", "storage.googleapis.com", "cloudkms.googleapis.com", "iamcredentials.googleapis.com", "sts.googleapis.com"]
}

variable "exclusions" {
  type = list(object({
    name        = string
    description = string
    filter      = string
  }))
  default = []
}

variable "acknowledge_high_volume" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}

# --- Operational settings ----------------------------------------------------
# Exposed deliberately: a customer on the button path could not previously change
# Pub/Sub retention -- which IS their entire recovery window -- or turn on
# dead-lettering, because the root did not pass them through.

variable "retention_days" {
  description = "Pub/Sub message retention, 1-31. THIS IS YOUR ENTIRE RECOVERY WINDOW: when the oldest unacked message reaches it, the data is deleted permanently with no error and no backfill. 7 gives you a long weekend."
  type        = number
  default     = 7
}

variable "ack_deadline_seconds" {
  type    = number
  default = 60
}

variable "enable_dead_letter" {
  description = "Send repeatedly-failing messages to a dead-letter topic instead of retrying forever. Pair it with gcp-monitoring-pipeline-health-alerts — a dead-letter topic nobody watches converts a loud failure into a silent one."
  type        = bool
  default     = false
}

variable "dead_letter_max_delivery_attempts" {
  type    = number
  default = 5
}

variable "topic_name" {
  description = "Renaming this FORCE-REPLACES the topic and cascades to the subscription, discarding every un-acked message. prevent_destroy blocks it; that is intentional."
  type        = string
  default     = "abstract-audit-logs"
}

variable "subscription_name" {
  type    = string
  default = "abstract-audit-logs-sub"
}

variable "sink_name" {
  type    = string
  default = "abstract-org-audit-sink"
}

variable "service_account_id" {
  type    = string
  default = "abstract-pubsub-reader"
}

variable "custom_filter" {
  description = "Replace the assembled filter entirely. Bypasses every guard in the catalog -- you own the volume."
  type        = string
  default     = ""
}

variable "platform_log_filters" {
  description = "Extra raw logName clauses the catalog does not cover, e.g. cloudaudit.googleapis.com%2Faccess_transparency"
  type        = list(string)
  default     = []
}
