variable "org_id" { type = string }

variable "log_project" {
  description = "Project holding the topic and subscription, and the billing project for the feed."
  type        = string
}

variable "subscriber_service_account_email" {
  description = "Abstract's identity, from 02-audit-logs-organization's abstract_onboarding output."
  type        = string
  # Defaulted to "" deliberately so the PRECONDITION fires with an explanation,
  # rather than Terraform's generic "No value for required variable" — which is
  # technically an error and practically useless.
  default = ""
}

variable "content_type" {
  description = <<-EOT
    What the feed carries.

      IAM_POLICY     Policy changes WITH the prior state. The highest-value one:
                     admin_activity tells you who called what API, this tells you
                     what the policy now IS. Three different API paths produce
                     three audit entries and one identical diff.
      RESOURCE       Full resource metadata on change. Inventory for an asset model.
      ORG_POLICY     Organization policy constraint changes.
      ACCESS_POLICY  VPC Service Controls and Access Context Manager changes.
      OS_INVENTORY   Installed packages and patches, where the Ops Agent runs.
      RELATIONSHIP   Resource-to-resource relationships.
  EOT
  type        = string
  default     = "IAM_POLICY"
}

variable "asset_types" {
  description = <<-EOT
    Asset types to watch, as regexes. EMPTY means everything, which on a large estate
    is a very large stream with a low signal ratio.

    A reasonable security-first start:
      ["cloudresourcemanager.googleapis.com/Project",
       "cloudresourcemanager.googleapis.com/Folder",
       "iam.googleapis.com/ServiceAccount",
       "iam.googleapis.com/ServiceAccountKey",
       "storage.googleapis.com/Bucket",
       "compute.googleapis.com/Firewall"]
  EOT
  type        = list(string)
  default = [
    "cloudresourcemanager.googleapis.com/Project",
    "cloudresourcemanager.googleapis.com/Folder",
    "iam.googleapis.com/ServiceAccount",
    "iam.googleapis.com/ServiceAccountKey",
    "storage.googleapis.com/Bucket",
    "compute.googleapis.com/Firewall",
  ]
}

variable "acknowledge_all_asset_types" {
  type    = bool
  default = false
}

variable "feed_id" {
  type    = string
  default = "abstract-asset-feed"
}

variable "topic_name" {
  type    = string
  default = "abstract-asset-changes"
}

variable "subscription_name" {
  type    = string
  default = "abstract-asset-changes-sub"
}

variable "retention_days" {
  type    = number
  default = 7
}

variable "ack_deadline_seconds" {
  type    = number
  default = 60
}

variable "labels" {
  type    = map(string)
  default = {}
}
