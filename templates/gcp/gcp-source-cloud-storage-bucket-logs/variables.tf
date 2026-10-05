variable "buckets" {
  description = "Buckets to watch, all in bucket_project."
  type        = list(string)
  default     = []
}

variable "bucket_map" {
  description = "bucket => owning project, when buckets span several projects. Each project has its OWN GCS service agent and each must be granted publisher — this is what makes that happen."
  type        = map(string)
  default     = {}
}

variable "bucket_project" {
  type    = string
  default = ""
}
variable "log_project" {
  description = "DEDICATED logging or security project holding this pipeline. Not a workload project. Find it with: gcloud projects list. If no dedicated logging project exists yet, create one first with deployments/01-logging-project (set create_project = true)."
  type        = string
}

variable "object_name_prefix" {
  description = "Scope to a prefix so irrelevant objects never generate a message you then pay to fetch."
  type        = string
  default     = ""
}

variable "cmek_crypto_key_id" {
  type    = string
  default = ""
}

variable "existing_service_account_email" {
  description = "Reuse Abstract's identity from the log-export deployment. Empty creates a new one."
  type        = string
  default     = ""
}

variable "acknowledge_bucket_sprawl" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}
