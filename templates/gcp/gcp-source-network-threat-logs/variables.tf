# --- Scope variables --------------------------------------------------------

variable "sink_scope" {
  description = <<-EOT
    Where the sink binds:
      organization    Everything, current and future, by containment (recommended).
      folder          All projects within a folder and subfolders.
      project         ONE project (requires acknowledge_pilot_scope = true).
  EOT
  type        = string
  default     = "organization"

  validation {
    condition     = contains(["organization", "folder", "project"], var.sink_scope)
    error_message = "sink_scope must be one of: organization, folder, project."
  }
}

variable "org_id" {
  description = "Organization ID. Required when sink_scope = organization. Find it with: gcloud organizations list"
  type        = string
  default     = ""
}

variable "folder_id" {
  description = "Folder ID. Required when sink_scope = folder."
  type        = string
  default     = ""
}

variable "sink_project" {
  description = "Project to bind the sink to when sink_scope = project. Defaults to log_project."
  type        = string
  default     = ""
}

variable "log_project" {
  description = "DEDICATED logging or security project holding the topic and subscription. Find it with: gcloud projects list."
  type        = string
}

variable "acknowledge_pilot_scope" {
  description = "Required when sink_scope = project to acknowledge single-project scope."
  type        = bool
  default     = false
}

# --- Telemetry and category toggles -----------------------------------------

variable "log_categories" {
  description = "Named sources to route from the log catalog. The network threat default is firewall, dns_queries, load_balancer (global external Application Load Balancer, with its Cloud Armor decisions) and load_balancer_regional_internal (regional external and internal Application Load Balancers)."
  type        = list(string)
  default     = ["firewall", "dns_queries", "load_balancer", "load_balancer_regional_internal"]
}

variable "platform_log_filters" {
  description = "Extra raw logName clauses to route. Defaults to Cloud IDS threat logs (ids.googleapis.com%2Fthreat)."
  type        = list(string)
  default     = ["ids.googleapis.com%2Fthreat"]
}

variable "audit_streams" {
  description = "Cloud Audit Log streams to route. Set to empty by default for network threat focus."
  type        = list(string)
  default     = []
}

variable "acknowledge_high_volume" {
  description = "Required when any high- or extreme-tier category is selected (the defaults dns_queries, load_balancer and load_balancer_regional_internal are high tier). These can dominate the bill; measure a 7-day baseline first."
  type        = bool
  default     = false
}

# --- Naming variables -------------------------------------------------------

variable "topic_name" {
  description = "Pub/Sub topic name for network threat logs."
  type        = string
  default     = "abstract-network-threats"
}

variable "subscription_name" {
  description = "Pub/Sub pull subscription name for Abstract."
  type        = string
  default     = "abstract-network-threats-sub"
}

variable "sink_name" {
  description = "Log sink name."
  type        = string
  default     = "abstract-network-threats-sink"
}

variable "service_account_id" {
  description = "Service account ID for Abstract subscriber identity."
  type        = string
  default     = "abstract-net-threat-reader"
}

# --- Operational settings ---------------------------------------------------

variable "retention_days" {
  description = "Pub/Sub message retention in days (1-31). This is your recovery window."
  type        = number
  default     = 7

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 31
    error_message = "retention_days must be between 1 and 31."
  }
}

variable "ack_deadline_seconds" {
  description = "Pub/Sub subscription acknowledgement deadline in seconds."
  type        = number
  default     = 60
}

variable "enable_dead_letter" {
  description = "Send repeatedly failing messages to a dead-letter topic."
  type        = bool
  default     = false
}

variable "dead_letter_max_delivery_attempts" {
  description = "Deliveries attempted before sending message to dead-letter topic (5-100)."
  type        = number
  default     = 5
}

variable "custom_filter" {
  description = "Override the assembled filter completely. Bypasses catalog compilation."
  type        = string
  default     = ""
}

variable "exclusions" {
  description = "Sink exclusion filters for known noise (e.g. internal health check probers)."
  type = list(object({
    name        = string
    description = string
    filter      = string
  }))
  default = []
}

variable "labels" {
  description = "Resource labels applied to Pub/Sub topic and subscription."
  type        = map(string)
  default     = {}
}
