variable "scope" {
  description = "organization | folder | project. Inheritance is ONE-WAY — a project can add Data Access logging but cannot disable what the organization enabled."
  type        = string
  default     = "organization"
}

variable "org_id" {
  type    = string
  default = ""
}
variable "folder_id" {
  type    = string
  default = ""
}
variable "project_id" {
  type    = string
  default = ""
}

variable "log_types" {
  description = "ADMIN_READ | DATA_WRITE | DATA_READ. ADMIN_WRITE is rejected — that is Admin Activity, always on."
  type        = list(string)
  default     = ["ADMIN_READ", "DATA_WRITE"]
}

variable "services" {
  description = "Services to turn Data Access logs on for, e.g. the guided setup's five: bigquery, storage, cloudkms, iam and sts (.googleapis.com). Empty means allServices: authoritative for every service, and with DATA_READ the expensive option that needs acknowledge_data_read. The template applies ONE log_types list and ONE exempted_members list to every service it names: name only services whose existing settings you accept being replaced by those, and leave out any service that already has DATA_READ or exempted members, or manage it only from a separate root with its own backend prefix, after removing it from this root's services."
  type        = list(string)
  default     = []
}

variable "exempted_members" {
  description = "Principals excluded. One chatty ETL service account can dominate DATA_READ volume while carrying no security signal — this is the most-missed cost lever."
  type        = list(string)
  default     = []
}

variable "acknowledge_data_read" {
  type    = bool
  default = false
}

variable "acknowledge_authoritative_overwrite" {
  description = "Required for every apply: the audit config is authoritative for EVERY service it names, so applying replaces the log types and exempted members already set on them, and destroy removes them. Read tools/gcp-guided-setup/preflight.sh output first. To offboard without changing logging, run terraform state rm 'module.audit_config'."
  type        = bool
  default     = false
}
