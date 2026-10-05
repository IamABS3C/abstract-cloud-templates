variable "log_project" { type = string }
variable "subscription_id" { type = string }
variable "topic_id" { type = string }

variable "prefix" {
  description = "Alert display-name prefix, so these are findable among a customer's existing policies."
  type        = string
  default     = "Abstract log pipeline"
}

variable "notification_channels" {
  description = "Monitoring notification channel IDs. Without at least one, every policy below fires into the void."
  type        = list(string)
  default     = []
}

variable "acknowledge_no_channel" {
  type    = bool
  default = false
}

variable "retention_days" {
  description = "Pub/Sub message retention. This is your ENTIRE recovery window, and it is what the stall alert counts down against."
  type        = number
  default     = 7
}

variable "unacked_age_threshold_seconds" {
  description = "Fire when the oldest unacked message is older than this. Default 1 hour — a small fraction of a 7-day window, so there is time to act before anything is lost."
  type        = number
  default     = 3600
}

variable "absence_threshold_seconds" {
  description = "Fire when nothing has been published for this long. Default 1 hour; org-wide audit logs are never genuinely quiet for that long."
  type        = number
  default     = 3600
}

variable "dead_letter_topic_id" {
  description = "Dead-letter topic to watch. Empty disables that policy."
  type        = string
  default     = ""
}
