#
# Multi-source: CloudTrail, GuardDuty and Security Hub from one security bucket
# into three Abstract configurations. All values below are examples — replace
# them with your own.
#
# Pattern A (direct notification): one bucket, one queue per source, one role,
# one configuration per source. Switch routing_mode to "sns" if you want a
# single destination rather than a single notification configuration, or
# "eventbridge" if the source list is going to keep growing. Nothing else in
# this file changes.
#

provider "aws" {
  region = "us-west-2"

  # Pin to the log-archive account so a stale AWS_PROFILE cannot deploy this
  # into the wrong one. Replace with your account id.
  allowed_account_ids = ["111122223333"]
}

module "abstract_ingest" {
  source = "../../"

  routing_mode = "direct"

  # The bucket the sources already write to (or will write to).
  bucket_name = "example-security-logs-111122223333-us-west-2"

  # Set false if another team owns the bucket. The module then builds everything
  # except the notification and emits the JSON to hand over, rather than
  # replacing whatever notifications the bucket already carries.
  manage_bucket_notification = true

  # Your tenant's Abstract-managed AWS account. PER-TENANT — fetch it live via
  # the Launchpad's Security lane (or POST /v1/integrations/permissions/aws/
  # launch-url); another tenant's value gives sts:AssumeRole AccessDenied.
  abstract_aws_account_id = "111122223333"

  sources = {
    cloudtrail = {
      prefix      = "cloudtrail/"
      integration = "default.cloudtrail.1_0_7"
      dataformat  = "json"
      description = "Managed parser. Carries the identity work that keeps SAML-federated logins resolving to the human rather than the assumed role."
    }

    guardduty = {
      prefix      = "guardduty/"
      integration = "default.guardduty.1_0_3"
      dataformat  = "conj"
      description = "Managed parser. Confirm the dataformat against a real object from your bucket before go-live."
    }

    securityhub = {
      prefix      = "securityhub/"
      integration = "default.aws_s3_sqs_source.1_2_0"
      dataformat  = "conj"
      description = "No managed Security Hub integration exists (confirmed against the live catalog) — generic S3 source plus a custom parser."
    }
  }

  name_prefix = "siem"
  role_name   = "SiemAbstractIntegrationRole"

  # A poison object that loops forever stalls the queue behind it. Every queue
  # here gets a DLQ and an alarm from day one — point this at a real SNS topic
  # before go-live.
  dlq_alarm_actions = []

  # If this bucket is SSE-KMS encrypted, set the CMK here AND add the statement
  # from the required_kms_key_policy_statement output to the key's own policy.
  # Without that, delivery fails before the message reaches the queue, so it
  # never reaches the DLQ and the alarms above cannot see it.
  kms_key_arn = null

  tags = {
    Owner   = "security-engineering"
    Purpose = "abstract-ingestion"
  }
}

output "abstract_configurations" {
  description = "One Abstract configuration per source. Never share an sqs_url between two configurations."
  value       = module.abstract_ingest.abstract_configurations
}
