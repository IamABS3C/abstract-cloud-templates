variable "bucket_map" {
  description = <<-EOT
    bucket name => owning project. Use this when buckets live in DIFFERENT projects:
    each project has its own GCS service agent, and each must be granted publisher
    separately. Granting only one leaves the other buckets with a notification config
    that creates successfully and delivers nothing.

      bucket_map = {
        "acme-vendor-logs"  = "acme-shared"
        "acme-appliance-out" = "acme-network"
      }

    Takes precedence over buckets + bucket_project.
  EOT
  type        = map(string)
  default     = {}
}

variable "buckets" {
  description = "Bucket names, all in bucket_project. Simple case. For buckets across several projects use bucket_map."
  type        = list(string)
  default     = []
}

variable "bucket_project" {
  description = "Project owning every bucket in `buckets`. Its GCS service agent is the principal that publishes. Ignored when bucket_map is set."
  type        = string
  default     = ""
}

variable "log_project" {
  description = "Project holding the topic and subscription. Can be the same as bucket_project."
  type        = string
}

variable "object_name_prefix" {
  description = "Only notify for objects under this prefix, AND scope Abstract's read permission to the same prefix via an IAM condition. Without a prefix the read grant is bucket-wide."
  type        = string
  default     = ""
}

variable "event_types" {
  description = "OBJECT_FINALIZE is object-created. Anything else describes an object you probably cannot then fetch."
  type        = list(string)
  default     = ["OBJECT_FINALIZE"]
}

variable "acknowledge_delete_events" {
  type    = bool
  default = false
}

variable "acknowledge_bucket_sprawl" {
  type    = bool
  default = false
}

variable "cmek_crypto_key_id" {
  description = "KMS key protecting the bucket, if any. Without the decrypter role every fetch fails with an error that blames Storage rather than KMS."
  type        = string
  default     = ""
}

variable "create_service_account" {
  description = "Create a new identity for Abstract. FALSE reuses one, which is preferable when the Pub/Sub pipeline already made one."
  type        = bool
  default     = true
}

variable "existing_service_account_email" {
  type    = string
  default = ""
}

variable "service_account_id" {
  type    = string
  default = "abstract-gcs-reader"
}

variable "topic_name" {
  type    = string
  default = "abstract-gcs-notifications"
}

variable "subscription_name" {
  type    = string
  default = "abstract-gcs-notifications-sub"
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "ack_deadline_seconds" {
  description = "Higher than the log-sink default on purpose: Abstract must FETCH each object after receiving the pointer, so the work per message is larger."
  type        = number
  default     = 120
}

variable "labels" {
  type    = map(string)
  default = {}
}
