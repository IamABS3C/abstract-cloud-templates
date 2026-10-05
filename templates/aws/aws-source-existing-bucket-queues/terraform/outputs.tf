output "abstract_configurations" {
  description = <<-EOT
    One entry per source, carrying exactly the fields an Abstract S3+SQS
    configuration needs. Create one configuration per entry.

    Reminder that outlives this module: never point two configurations at the
    same sqs_url. SQS is competing-consumer, so they would split the stream at
    random and neither would report an error.
  EOT

  value = {
    for k, v in var.sources : k => {
      # -> Abstract field: name
      suggested_name = "${k}-s3-sqs"
      # -> Abstract field: integration_id
      integration_id = v.integration
      # -> Abstract field: sqs_url  (the ONLY source selector that exists)
      sqs_url = aws_sqs_queue.source[k].url
      # -> Abstract field: region
      region = data.aws_region.current.region
      # -> Abstract field: s3_bucket
      s3_bucket = var.bucket_name
      # -> Abstract field: sqs_queue_arn
      sqs_queue_arn = aws_sqs_queue.source[k].arn
      # -> Abstract field: role_arn
      role_arn = aws_iam_role.abstract.arn
      # -> Abstract field: dataformat
      dataformat = v.dataformat

      # Operational context, not configuration fields.
      s3_prefix   = v.prefix
      s3_suffix   = v.suffix
      dlq_url     = aws_sqs_queue.dlq[k].url
      description = v.description
    }
  }
}

output "external_id" {
  description = "sts:ExternalId -> Abstract field external_id. Identical for every configuration created against this role."
  value       = local.external_id
  sensitive   = true
}

output "role_arn" {
  description = "Cross-account role ARN -> Abstract field role_arn. Shared by every configuration."
  value       = aws_iam_role.abstract.arn
}

output "routing_mode" {
  description = "Which routing layer was built."
  value       = var.routing_mode
}

output "sns_topic_arn" {
  description = "Fan-out topic ARN. Null unless routing_mode is \"sns\"."
  value       = var.routing_mode == "sns" ? aws_sns_topic.fanout[0].arn : null
}

output "eventbridge_rule_arns" {
  description = "Per-source rule ARNs. Empty unless routing_mode is \"eventbridge\"."
  value       = var.routing_mode == "eventbridge" ? { for k, r in aws_cloudwatch_event_rule.source : k => r.arn } : {}
}

output "dead_letter_queues" {
  description = "Per-source DLQ URLs. Anything landing here is an object Abstract could not collect."
  value       = { for k, q in aws_sqs_queue.dlq : k => q.url }
}

output "bucket_notification_plan" {
  description = <<-EOT
    Populated only when manage_bucket_notification is false and the routing mode
    needs a notification. Hand this to whoever owns the bucket, or apply it with:

      aws s3api put-bucket-notification-configuration \
        --bucket <bucket> --notification-configuration file://plan.json

    A bucket has exactly ONE notification configuration and this call REPLACES
    it wholesale. Read the current one first and merge, or you will delete
    another team's notifications:

      aws s3api get-bucket-notification-configuration --bucket <bucket>
  EOT

  value = (!var.manage_bucket_notification && contains(["direct", "sns"], var.routing_mode)) ? local.notification_plan_json : null
}

output "required_kms_key_policy_statement" {
  description = <<-EOT
    Null unless kms_key_arn is set.

    This module cannot write your CMK's key policy - key policies are
    authoritative and usually owned by another team, and a careless write locks
    people out of their own key. But delivery WILL fail without this statement,
    and it fails quietly: the producer gets KMS.AccessDeniedException, the
    message never reaches the queue, so it never reaches the dead-letter queue
    either and no alarm in this module can see it.

    Add this to the CMK's key policy before go-live, then send a probe object.
  EOT

  value = var.kms_key_arn == null ? null : jsonencode({
    Sid    = "AllowAbstractIngestionProducerToUseTheKey"
    Effect = "Allow"
    Principal = {
      Service = (
        var.routing_mode == "direct" ? "s3.amazonaws.com" :
        var.routing_mode == "sns" ? "sns.amazonaws.com" :
        "events.amazonaws.com"
      )
    }
    Action = [
      "kms:GenerateDataKey*",
      "kms:Decrypt",
    ]
    Resource = "*"
    Condition = {
      StringEquals = {
        "aws:SourceAccount" = data.aws_caller_identity.current.account_id
      }
    }
  })
}

output "manual_bucket_steps" {
  description = <<-EOT
    Commands nobody but the bucket owner should run, populated when this module
    was told not to manage the bucket notification.

    Every one of these is a read-modify-write, because
    put-bucket-notification-configuration REPLACES the bucket's entire
    notification configuration. That applies to enabling EventBridge too: it is
    a logically independent flag, but it is written by the same wholesale PUT,
    so sending just {"EventBridgeConfiguration":{}} deletes every queue and
    topic notification on the bucket.
  EOT

  value = var.manage_bucket_notification ? [] : (
    var.routing_mode == "eventbridge" ? [
      "# Enable EventBridge WITHOUT destroying existing notifications.",
      "aws s3api get-bucket-notification-configuration --bucket ${var.bucket_name} > current.json",
      "jq '.EventBridgeConfiguration = {} | del(.ResponseMetadata)' current.json > merged.json",
      "aws s3api put-bucket-notification-configuration --bucket ${var.bucket_name} --notification-configuration file://merged.json",
      "",
      "# Note: once enabled, S3 sends ALL event types to EventBridge. Selectivity",
      "# lives entirely in the rules, which this module already created.",
      ] : [
      "# Merge the queue entries in bucket_notification_plan into what is already there.",
      "aws s3api get-bucket-notification-configuration --bucket ${var.bucket_name} > current.json",
      "# Hand current.json plus the bucket_notification_plan output to the bucket owner.",
      "# There is no conditional write on this subresource, so two teams doing",
      "# read-modify-write concurrently is a lost-update race. Coordinate.",
      "aws s3api put-bucket-notification-configuration --bucket ${var.bucket_name} --notification-configuration file://merged.json",
    ]
  )
}

output "verification_commands" {
  description = "Copy-paste checks to run after apply, before declaring the pipeline healthy."

  value = concat(
    [
      "# 1. Confirm the bucket notification is what you expect (and nothing else was clobbered)",
      "aws s3api get-bucket-notification-configuration --bucket ${var.bucket_name}",
      "",
      "# 2. Drop a probe object into each prefix and confirm exactly one queue receives it",
    ],
    flatten([
      for k, v in var.sources : [
        "echo '{\"probe\":\"${k}\"}' | aws s3 cp - s3://${var.bucket_name}/${v.prefix}_abstract-probe.json",
        "aws sqs get-queue-attributes --queue-url ${aws_sqs_queue.source[k].url} --attribute-names ApproximateNumberOfMessages",
      ]
    ]),
    [
      "",
      "# 3. Confirm Abstract can actually assume the role BEFORE creating configurations.",
      "#    /v2/configurations/validate performs a real sts:AssumeRole.",
      "#    Note: config create/validate are MULTIPART FORM, with parameters as a JSON-encoded string.",
      "",
      "# 4. Every DLQ should be empty.",
    ],
    [for k, q in aws_sqs_queue.dlq : "aws sqs get-queue-attributes --queue-url ${q.url} --attribute-names ApproximateNumberOfMessages"]
  )
}
