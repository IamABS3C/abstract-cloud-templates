variable "create_project" {
  description = "FALSE (default) only enables APIs on an existing project. TRUE also creates it, which needs project-creator rights; billing_account_id is optional (see its description)."
  type        = bool
  default     = false
}

variable "project_id" { type = string }
variable "project_name" {
  type    = string
  default = "Abstract Security Logging"
}
variable "org_id" {
  type    = string
  default = ""
}
variable "folder_id" {
  type    = string
  default = ""
}
variable "billing_account_id" {
  description = "Billing account to link when create_project = true. The log pipeline itself was measured delivering on a project with billing disabled (docs/public/gcp/VERIFIED.md), but an API that requires billing cannot be enabled without one. Find it with: gcloud billing accounts list"
  type        = string
  default     = ""
}
variable "enable_workspace_api" {
  type    = bool
  default = false
}
variable "enable_scc_api" {
  type    = bool
  default = false
}
variable "labels" {
  type    = map(string)
  default = {}
}
