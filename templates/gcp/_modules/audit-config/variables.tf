variable "scope" {
  description = "organization | folder | project. Inheritance is one-way: a project can ADD Data Access logging but cannot disable what the organization enabled."
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
  description = <<-EOT
    Which Data Access log types to enable.

      ADMIN_READ  metadata/config reads. Low volume, high signal. Safe everywhere.
      DATA_WRITE  data-modifying operations. Moderate.
      DATA_READ   data reads. THE cost driver — and also where the exfiltration
                  signal lives, so scope it rather than refusing it.

    ADMIN_WRITE is not accepted: that is Admin Activity, always on, and cannot be
    disabled by anyone.
  EOT
  type        = list(string)
  default     = ["ADMIN_READ", "DATA_WRITE"]
}

variable "services" {
  description = <<-EOT
    Services to enable it for, e.g. bigquery.googleapis.com. EMPTY means allServices,
    which with DATA_READ is the expensive option and requires acknowledge_data_read.

    Recommended opening position: ADMIN_READ + DATA_WRITE on allServices, and DATA_READ
    only on bigquery.googleapis.com and storage.googleapis.com.
  EOT
  type        = list(string)
  default     = []
}

variable "exempted_members" {
  description = "Principals excluded from this logging, e.g. serviceAccount:noisy-etl@project.iam.gserviceaccount.com. The most-missed cost lever — one chatty ETL account can dominate DATA_READ volume while carrying no security signal."
  type        = list(string)
  default     = []
}

variable "acknowledge_data_read" {
  description = "Required for DATA_READ on allServices."
  type        = bool
  default     = false
}

variable "acknowledge_authoritative_overwrite" {
  description = "Required when services resolves to allServices. This resource is authoritative per service — applying a narrower set of log types REMOVES the ones you did not list, including ones a landing zone or CIS benchmark put there. Read preflight.sh output before setting this."
  type        = bool
  default     = false
}
