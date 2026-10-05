variable "create_project" {
  description = "FALSE (default) only enables APIs on an existing project. TRUE also creates it, which needs billing_account_id and project-creator rights."
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
  description = "Required when create_project = true. A project with no billing account cannot publish to Pub/Sub. Globally unique, 6-30 chars, lowercase. This is the ID you are creating, not one to look up — confirm it is still free with: gcloud projects list"
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
