variable "org_id" {
  description = "Organization ID the archive sink binds to. Find it with: gcloud organizations list"
  type        = string
}
variable "log_project" {
  description = "DEDICATED logging or security project holding the archive sink. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with deployments/01-logging-project (set create_project = true) — do not point this at a workload project."
  type        = string
}

variable "archive_bucket_name" {
  description = "Globally unique across ALL of GCS, so prefix it with your org: acme-abstract-audit-archive. Existing buckets: gcloud storage buckets list"
  type        = string
}

variable "filter" {
  description = "Fallback filter, used only when remote_state_bucket and stream_filter are both empty. Prefer remote state: an archive that quietly captures LESS than the stream is worse than no archive, because you will trust it during an investigation."
  type        = string
  default     = ""
}

variable "sink_name" {
  type    = string
  default = "abstract-org-audit-sink"
}

variable "archive_bucket_location" {
  description = "US, EU, or a region. Consider data-residency obligations before defaulting."
  type        = string
  default     = "US"
}

variable "archive_retention_days" {
  description = "Retention period in days; 0 disables. On its own this is a DEFAULT that anyone with storage.buckets.update can shorten or remove. Pair it with archive_retention_locked to make it immutable."
  type        = number
  default     = 0
}

variable "archive_nearline_after_days" {
  type    = number
  default = 30
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "archive_retention_locked" {
  description = "LOCK the retention policy. IRREVERSIBLE — once set, the period cannot be shortened or removed for the life of the bucket, by anyone. This is what makes the archive evidentiary; it is also why it is not the default."
  type        = bool
  default     = false
}

variable "archive_versioning" {
  type    = bool
  default = true
}

variable "archive_cmek_key" {
  description = "Customer-managed KMS key. The Cloud Storage service agent needs roles/cloudkms.cryptoKeyEncrypterDecrypter on it."
  type        = string
  default     = ""
}

variable "stream_filter" {
  description = "Optional. Paste `terraform output -raw effective_filter` from 02-audit-logs-organization here and a check block asserts the archive matches the stream. Empty skips the check — but then nothing stops the two diverging."
  type        = string
  default     = ""
}

variable "remote_state_bucket" {
  description = "GCS bucket holding 02-audit-logs-organization's state. Set it and the value below is READ rather than retyped. Empty uses the literal."
  type        = string
  default     = ""
}

variable "remote_state_prefix" {
  description = "State key of 02-audit-logs-organization. It keeps that folder's original name, 01-organization, so existing state is found."
  type        = string
  default     = "01-organization"
}
