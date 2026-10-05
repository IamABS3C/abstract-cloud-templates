#
# Pattern A - direct bucket notification, on a bucket another team owns.
#
# manage_bucket_notification = false is the important line. It builds every
# queue, policy, alarm, and the IAM role, but does NOT write the bucket
# notification, because a bucket has exactly one notification configuration and
# writing it would delete whatever the owning team put there.
#
# Terraform emits the JSON to hand them instead.
#

provider "aws" {
  region = "us-east-1"
}

module "abstract_ingest" {
  source = "../../"

  routing_mode               = "direct"
  bucket_name                = "example-security-logs"
  manage_bucket_notification = false

  # PER-TENANT. Retrieve with an API key for the tenant you are onboarding.
  abstract_aws_account_id = "000000000000"

  sources = {
    cloudtrail = {
      prefix      = "cloudtrail/"
      integration = "default.cloudtrail.1_0_6"
    }
    guardduty = {
      prefix      = "guardduty/"
      integration = "default.guardduty.1_0_3"
    }
  }

  tags = {
    Owner   = "security-engineering"
    Purpose = "abstract-ingestion"
  }
}

output "abstract_configurations" {
  value = module.abstract_ingest.abstract_configurations
}

output "hand_this_to_the_bucket_owner" {
  description = "Merge into the bucket's existing notification configuration. Do not replace it wholesale."
  value       = module.abstract_ingest.bucket_notification_plan
}
