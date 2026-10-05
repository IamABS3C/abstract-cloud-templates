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
  description = "Empty means allServices. With DATA_READ that is the expensive option and needs acknowledge_data_read."
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
  description = "Required for allServices. See scripts/preflight.sh output first — this resource can REMOVE audit log types it does not list."
  type        = bool
  default     = false
}
