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

    Recommended opening position, the guided setup's five: bigquery.googleapis.com,
    storage.googleapis.com, cloudkms.googleapis.com, iam.googleapis.com (token minting) and
    sts.googleapis.com (federation), with ADMIN_READ + DATA_WRITE. Every service named here,
    allServices included, is managed authoritatively.

    This module applies ONE log_types list and ONE exempted_members list to every service it
    names. Name only services whose existing settings you accept being replaced by those; leave
    out any service that already has DATA_READ or exempted members, or manage it only from a
    separate root with its own backend prefix, after removing it from this root's services. Token minting is turned on as iam.googleapis.com: iamcredentials.googleapis.com is
    refused, because Google records nothing for it on its own.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = !contains(var.services, "iamcredentials.googleapis.com")
    error_message = "iamcredentials.googleapis.com cannot be turned on by itself: Google records token minting (GenerateAccessToken, SignBlob, SignJwt) only through the IAM API. Name iam.googleapis.com instead; the events still carry serviceName iamcredentials.googleapis.com, which is what the sink routes (identity_access)."
  }
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
  description = "Required for every apply. This resource is authoritative for EVERY service it names, not only allServices: applying REPLACES the log types and exempted members already set on those services (including ones a landing zone or CIS benchmark put there) with this module's single log_types and exempted_members lists, and destroy REMOVES them. Read tools/gcp-guided-setup/preflight.sh output before setting this. To offboard without changing logging, run terraform state rm 'module.audit_config' instead of destroy."
  type        = bool
  default     = false
}
