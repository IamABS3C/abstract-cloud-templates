variable "billing_account_id" {
  description = "GCP billing account ID formatted e.g. 012345-567890-ABCDEF. Find it with: gcloud billing accounts list"
  type        = string
}

variable "log_project" {
  description = "DEDICATED logging or security project holding the topic and subscription. Not a workload project — Pub/Sub publish quota is consumed here, and a workload owner should not be able to read or break the security pipeline. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with deployments/01-logging-project (set create_project = true) — do not point this at a workload project."
  type        = string
}

variable "topic_name" {
  description = "Renaming this FORCE-REPLACES the topic and cascades to the subscription, discarding every un-acked message. prevent_destroy blocks it; that is intentional."
  type        = string
  default     = "abstract-billing-audit-logs"
}

variable "subscription_name" {
  description = "Pub/Sub subscription name Abstract pulls from."
  type        = string
  default     = "abstract-billing-audit-logs-sub"
}

variable "sink_name" {
  description = "Name of the Cloud Logging billing account sink."
  type        = string
  default     = "abstract-billing-audit-sink"
}

variable "service_account_id" {
  description = "Service account ID created for Abstract Security pull access."
  type        = string
  default     = "abstract-billing-reader"
}

variable "retention_days" {
  description = "Pub/Sub message retention, 1-31. THIS IS YOUR ENTIRE RECOVERY WINDOW: when the oldest unacked message reaches it, the data is deleted permanently with no error and no backfill. 7 gives you a long weekend."
  type        = number
  default     = 7
}

variable "ack_deadline_seconds" {
  description = "Pub/Sub subscriber acknowledgement deadline in seconds."
  type        = number
  default     = 60
}

variable "labels" {
  description = "Resource labels applied to the Pub/Sub topic and subscription."
  type        = map(string)
  default     = {}
}

variable "log_categories" {
  description = "Named sources to route. Cloud Billing writes Admin Activity audit logs (IAM policy changes, project billing links and unlinks, account create, close, reopen, rename and move) and Data Access audit logs, and no System Event logs (https://docs.cloud.google.com/billing/docs/audit-logging). Defaults to admin_activity. See modules/log-export/log_catalog.tf for the catalog."
  type        = list(string)
  default     = ["admin_activity"]
}

variable "exclusions" {
  description = "Sink exclusion filters for known noise. Exclusions cost nothing to evaluate while ingestion and Pub/Sub throughput are billed. Max 50 per sink."
  type = list(object({
    name        = string
    description = string
    filter      = string
  }))
  default = []
}

variable "custom_filter" {
  description = "Replace the assembled filter entirely. Bypasses every guard in the catalog -- you own the volume."
  type        = string
  default     = ""
}
