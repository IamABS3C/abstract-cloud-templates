variable "create_project" {
  description = "Create the logging project. FALSE (default) uses an existing one — which is the normal case."
  type        = bool
  default     = false
}

variable "project_id" {
  description = "Project ID to create or use. Globally unique when creating."
  type        = string
}

variable "project_name" {
  description = "Display name when creating."
  type        = string
  default     = "Abstract Security Logging"
}

variable "org_id" {
  type    = string
  default = ""
}

variable "folder_id" {
  description = "Create the project under this folder instead of directly under the org."
  type        = string
  default     = ""
}

variable "billing_account_id" {
  description = "Billing account to link when create_project = true. The log pipeline itself was measured delivering on a project with billing disabled (docs/public/gcp/VERIFIED.md), but an API that requires billing cannot be enabled without one, and Google's Cloud Storage guides ask for billing before a bucket, such as a Terraform state bucket, is created in the project. Find it with: gcloud billing accounts list"
  type        = string
  default     = ""
}

variable "deletion_policy" {
  description = "PREVENT (default) refuses to delete the project via Terraform. DELETE allows it. PREVENT is the right default for a project holding an audit pipeline."
  type        = string
  default     = "PREVENT"
}

variable "enable_workspace_api" {
  type    = bool
  default = false
}

variable "enable_scc_api" {
  type    = bool
  default = false
}

variable "additional_apis" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}
