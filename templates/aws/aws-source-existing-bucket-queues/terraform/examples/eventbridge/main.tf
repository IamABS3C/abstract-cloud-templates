#
# Pattern C - EventBridge routing for a multi-source security bucket.
#
# Recommended when the source list will grow, or when any source needs
# filtering that a prefix cannot express.
#

provider "aws" {
  region = "us-east-1"
}

module "abstract_ingest" {
  source = "../../"

  routing_mode = "eventbridge"
  bucket_name  = "example-security-logs"

  # PER-TENANT. Retrieve with an API key for the tenant you are onboarding:
  #   POST /v1/integrations/permissions/aws/launch-url?download_template=true
  abstract_aws_account_id = "000000000000"

  sources = {
    cloudtrail = {
      prefix      = "AWSLogs/"
      suffix      = ".json.gz"
      integration = "default.cloudtrail.1_0_6"
      description = "Organization CloudTrail. Managed parser; do not use the generic source here."
    }

    guardduty = {
      prefix      = "guardduty/"
      integration = "default.guardduty.1_0_3"
      description = "GuardDuty findings export."
    }

    securityhub = {
      prefix      = "securityhub/"
      integration = "default.aws_s3_sqs_source.1_2_0"
      dataformat  = "nd"
      description = "Security Hub findings. No dedicated integration exists, so the generic S3+SQS source carries a custom parser."
    }
  }

  dlq_alarm_actions = [] # Put a real SNS topic here before go-live.

  tags = {
    Owner   = "security-engineering"
    Purpose = "abstract-ingestion"
  }
}

output "abstract_configurations" {
  description = "One Abstract configuration per entry. Never share an sqs_url between two configurations."
  value       = module.abstract_ingest.abstract_configurations
}

output "external_id" {
  value     = module.abstract_ingest.external_id
  sensitive = true
}

output "next_steps" {
  value = module.abstract_ingest.verification_commands
}
