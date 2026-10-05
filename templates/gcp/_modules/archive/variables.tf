variable "enable_gcs_archive" {
  description = <<-EOT
    Add a SECOND sink writing to Cloud Storage for cold storage and backfill.

    NOT the streaming path -- GCS batches, so detection latency becomes minutes to hours.
    Reserve it for archive and replay. Organization scope only, for now.
  EOT
  type        = bool
  default     = false
}
variable "archive_bucket_name" {
  description = "Globally unique bucket name for the archive sink."
  type        = string
  default     = ""
}
variable "archive_bucket_location" {
  description = "Bucket location, e.g. US, EU, us-central1. Consider data-residency obligations."
  type        = string
  default     = "US"
}
variable "archive_retention_days" {
  description = "Retention period in days; 0 disables. On its own this is a DEFAULT, not immutability -- it can be shortened or removed by anyone with storage.buckets.update. Set archive_retention_locked to make it real."
  type        = number
  default     = 0
}
variable "archive_nearline_after_days" {
  description = "Transition archived objects to NEARLINE after this many days."
  type        = number
  default     = 30
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

variable "sink_name" {
  type    = string
  default = "abstract-org-audit-sink"
}

variable "sink_scope" {
  type    = string
  default = "organization"
}

variable "filter" {
  description = "The Cloud Logging filter. Passed in from log-export so archive and stream cannot silently diverge."
  type        = string
}

variable "archive_retention_locked" {
  description = <<-EOT
    LOCK the retention policy. THIS IS IRREVERSIBLE.

    Once locked, the retention period cannot be shortened or removed for the LIFE OF THE
    BUCKET -- not by you, not by an org admin, not by Google support. Objects cannot be
    deleted before it expires, and the bucket cannot be deleted while it holds them.

    That is exactly what makes the archive evidentiary, and exactly why it is not the
    default. Set it only when you have decided the retention period is correct and you
    have accepted that a mistake is permanent.
  EOT
  type        = bool
  default     = false
}

variable "archive_versioning" {
  description = "Keep superseded object versions. On for an evidentiary archive by default."
  type        = bool
  default     = true
}

variable "archive_cmek_key" {
  description = "Customer-managed KMS key for the bucket. The Cloud Storage service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = ""
}
