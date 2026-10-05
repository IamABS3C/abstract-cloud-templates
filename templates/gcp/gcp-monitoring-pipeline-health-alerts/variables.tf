variable "log_project" {
  description = "DEDICATED logging or security project holding this pipeline. Not a workload project. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with deployments/01-logging-project (set create_project = true)."
  type        = string
}

variable "topic_id" {
  description = "Topic NAME (not the full path), from 02-audit-logs-organization."
  type        = string
  default     = "abstract-audit-logs"
}

variable "subscription_id" {
  description = "Subscription NAME (not the full path), from 02-audit-logs-organization."
  type        = string
  default     = "abstract-audit-logs-sub"
}

variable "dead_letter_topic_id" {
  type    = string
  default = ""
}

variable "notification_channels" {
  description = "Channel IDs. List them with: gcloud beta monitoring channels list --format='value(name)'"
  type        = list(string)
  default     = []
}

variable "acknowledge_no_channel" {
  type    = bool
  default = false
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "unacked_age_threshold_seconds" {
  type    = number
  default = 3600
}

variable "absence_threshold_seconds" {
  type    = number
  default = 3600
}

variable "prefix" {
  type    = string
  default = "Abstract log pipeline"
}
