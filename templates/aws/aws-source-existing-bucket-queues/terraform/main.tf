#
# Abstract Security - multi-source S3 + SQS ingestion routing
#
# One security bucket holds several log sources under different key prefixes.
# Abstract needs to ingest each source with its own parser.
#
# The load-bearing constraint, verified against the live integration schemas for
# default.aws_s3_sqs_source.1_2_0 and default.cloudtrail.1_0_6: the ONLY source
# selector an Abstract S3+SQS configuration exposes is `sqs_url`. There is no
# prefix, path, or filter parameter. A configuration's scope IS a queue's
# contents.
#
# Therefore N sources needing N parsers require N queues. Never point two
# configurations at one queue: SQS is a competing-consumer service, so each
# poller deletes what it takes and the two configurations split the stream at
# random with no error raised anywhere.
#
# This module builds those N queues and one of three routing layers in front of
# them, selected by var.routing_mode.
#

locals {
  # Trailing-hyphen-safe name builder shared by every resource.
  name = var.name_prefix

  bucket_arn = "arn:${data.aws_partition.current.partition}:s3:::${var.bucket_name}"

  external_id = var.external_id != null ? var.external_id : random_uuid.external_id[0].result

  # Only "direct" and "sns" write QueueConfigurations/TopicConfigurations into
  # the bucket notification. "eventbridge" sets the independent flag instead.
  manages_notification = var.manage_bucket_notification && contains(["direct", "sns"], var.routing_mode)

  queue_arns = [for k, q in aws_sqs_queue.source : q.arn]

  # Rendered for humans when Terraform is not allowed to own the notification.
  #
  # Each branch is encoded to a STRING rather than returned as an object. The three
  # shapes are genuinely different ({QueueConfigurations}, {TopicConfigurations}, {})
  # and a conditional requires consistent types across its branches, so returning the
  # objects raised "true and false result expressions must have consistent types" the
  # moment the expression was actually evaluated. `validate` never evaluates it, so
  # this only surfaced under `tofu test`.
  notification_plan_json = (
    var.routing_mode == "direct" ? jsonencode({
      QueueConfigurations = [
        for k, v in var.sources : {
          Id       = "abstract-${k}"
          QueueArn = aws_sqs_queue.source[k].arn
          Events   = ["s3:ObjectCreated:*"]
          Filter = {
            Key = {
              FilterRules = concat(
                [{ Name = "prefix", Value = v.prefix }],
                v.suffix != "" ? [{ Name = "suffix", Value = v.suffix }] : []
              )
            }
          }
        }
      ]
    }) :
    var.routing_mode == "sns" ? jsonencode({
      TopicConfigurations = [
        {
          Id       = "abstract-fanout"
          TopicArn = aws_sns_topic.fanout[0].arn
          Events   = ["s3:ObjectCreated:*"]
        }
      ]
    }) :
    ""
  )
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "random_uuid" "external_id" {
  count = var.external_id == null ? 1 : 0
}

# ---------------------------------------------------------------------------
# Per-source queues. Created in every routing mode - this is the invariant.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  for_each = var.sources

  name                      = "${local.name}-${each.key}-dlq"
  message_retention_seconds = 1209600 # 14 days, the maximum. A DLQ you drain slowly is the point.
  sqs_managed_sse_enabled   = var.kms_key_arn == null
  kms_master_key_id         = var.kms_key_arn

  tags = merge(var.tags, {
    Name              = "${local.name}-${each.key}-dlq"
    AbstractSource    = each.key
    AbstractQueueRole = "dead-letter"
  })
}

resource "aws_sqs_queue" "source" {
  for_each = var.sources

  name                       = "${local.name}-${each.key}"
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  sqs_managed_sse_enabled    = var.kms_key_arn == null
  kms_master_key_id          = var.kms_key_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[each.key].arn
    maxReceiveCount     = var.dlq_max_receive_count
  })

  tags = merge(var.tags, {
    Name                = "${local.name}-${each.key}"
    AbstractSource      = each.key
    AbstractPrefix      = each.value.prefix
    AbstractIntegration = each.value.integration
    AbstractQueueRole   = "live"
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  for_each = var.sources

  queue_url = aws_sqs_queue.dlq[each.key].id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.source[each.key].arn]
  })
}

# ---------------------------------------------------------------------------
# Queue policies. The sender principal differs per routing mode.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "queue" {
  for_each = var.sources

  dynamic "statement" {
    for_each = var.routing_mode == "direct" ? [1] : []
    content {
      sid       = "AllowS3Notification"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.source[each.key].arn]

      principals {
        type        = "Service"
        identifiers = ["s3.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = [local.bucket_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.routing_mode == "sns" ? [1] : []
    content {
      sid       = "AllowSNSFanout"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.source[each.key].arn]

      principals {
        type        = "Service"
        identifiers = ["sns.amazonaws.com"]
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [aws_sns_topic.fanout[0].arn]
      }
    }
  }

  dynamic "statement" {
    for_each = var.routing_mode == "eventbridge" ? [1] : []
    content {
      sid       = "AllowEventBridgeRule"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [aws_sqs_queue.source[each.key].arn]

      principals {
        type        = "Service"
        identifiers = ["events.amazonaws.com"]
      }

      condition {
        test     = "ArnEquals"
        variable = "aws:SourceArn"
        values   = [aws_cloudwatch_event_rule.source[each.key].arn]
      }
    }
  }
}

resource "aws_sqs_queue_policy" "source" {
  for_each = var.sources

  queue_url = aws_sqs_queue.source[each.key].id
  policy    = data.aws_iam_policy_document.queue[each.key].json
}

# ---------------------------------------------------------------------------
# Pattern A - direct bucket notification, one prefix-filtered entry per source.
#
# A bucket has exactly ONE notification configuration. This single resource
# holds every source's entry, which is why "one notification configuration" is
# already satisfied here - it is not a reason to reach for SNS or EventBridge.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "direct" {
  count = local.manages_notification && var.routing_mode == "direct" ? 1 : 0

  bucket = var.bucket_name

  dynamic "queue" {
    for_each = var.sources
    content {
      id            = "abstract-${queue.key}"
      queue_arn     = aws_sqs_queue.source[queue.key].arn
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = queue.value.prefix
      filter_suffix = queue.value.suffix != "" ? queue.value.suffix : null
    }
  }

  depends_on = [aws_sqs_queue_policy.source]
}

# ---------------------------------------------------------------------------
# Pattern B - one SNS topic, fanned out to per-source queues by a MessageBody
# filter policy on the S3 object key.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "fanout" {
  count = var.routing_mode == "sns" ? 1 : 0

  name              = "${local.name}-s3-fanout"
  kms_master_key_id = var.kms_key_arn

  tags = merge(var.tags, { Name = "${local.name}-s3-fanout" })
}

data "aws_iam_policy_document" "fanout" {
  count = var.routing_mode == "sns" ? 1 : 0

  statement {
    sid       = "AllowS3Publish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.fanout[0].arn]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bucket_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "fanout" {
  count = var.routing_mode == "sns" ? 1 : 0

  arn    = aws_sns_topic.fanout[0].arn
  policy = data.aws_iam_policy_document.fanout[0].json
}

resource "aws_sns_topic_subscription" "source" {
  for_each = var.routing_mode == "sns" ? var.sources : {}

  topic_arn = aws_sns_topic.fanout[0].arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.source[each.key].arn

  # Deliver the bare S3 event, not the SNS envelope, so the queue payload is
  # byte-identical to what Pattern A produces and Abstract sees one shape
  # regardless of which routing mode is in use.
  raw_message_delivery = true

  # Filter on the event body rather than message attributes: S3 does not set
  # a message attribute carrying the object key, so attribute-scoped filtering
  # cannot express "this prefix".
  #
  # A list of matchers is OR, not AND, so [{prefix=...},{suffix=...}] would
  # match everything under the prefix PLUS everything with that suffix anywhere
  # in the bucket. When both are needed, one wildcard matcher expresses the
  # conjunction correctly.
  filter_policy_scope = "MessageBody"
  filter_policy = jsonencode({
    Records = {
      s3 = {
        object = {
          key = [
            each.value.suffix != ""
            ? { wildcard = "${each.value.prefix}*${each.value.suffix}" }
            : { prefix = each.value.prefix }
          ]
        }
      }
    }
  })
}

resource "aws_s3_bucket_notification" "sns" {
  count = local.manages_notification && var.routing_mode == "sns" ? 1 : 0

  bucket = var.bucket_name

  topic {
    id        = "abstract-fanout"
    topic_arn = aws_sns_topic.fanout[0].arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.fanout]
}

# ---------------------------------------------------------------------------
# Pattern C - EventBridge, one rule per source.
#
# Filtering is no longer limited to prefix and suffix: rules can match object
# size, requester, source IP, or anything-but a noisy subpath, and additional
# non-SQS targets can be attached later without touching the bucket.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "eventbridge" {
  count = var.manage_bucket_notification && var.routing_mode == "eventbridge" ? 1 : 0

  bucket      = var.bucket_name
  eventbridge = true
}

resource "aws_cloudwatch_event_rule" "source" {
  for_each = var.routing_mode == "eventbridge" ? var.sources : {}

  name        = "${local.name}-${each.key}"
  description = "Route s3://${var.bucket_name}/${each.value.prefix} to the Abstract ${each.key} queue"

  # As with SNS, a list of matchers is OR. Use a single wildcard matcher when
  # both a prefix and a suffix must hold.
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [var.bucket_name] }
      object = {
        key = [
          each.value.suffix != ""
          ? { wildcard = "${each.value.prefix}*${each.value.suffix}" }
          : { prefix = each.value.prefix }
        ]
      }
    }
  })

  tags = merge(var.tags, {
    Name           = "${local.name}-${each.key}"
    AbstractSource = each.key
  })
}

resource "aws_cloudwatch_event_target" "source" {
  for_each = var.routing_mode == "eventbridge" ? var.sources : {}

  rule = aws_cloudwatch_event_rule.source[each.key].name
  arn  = aws_sqs_queue.source[each.key].arn

  # An EventBridge S3 event carries bucket and key at detail.bucket.name and
  # detail.object.key. A native S3 notification carries them at
  # Records[].s3.bucket.name and Records[].s3.object.key. Different shapes, and
  # understanding the EventBridge one is a PER-INTEGRATION capability:
  # default.vpc_flow added it in 1.0.1 as a named feature, which means
  # integrations that never did that work handle only the direct S3 shape.
  #
  # Reshaping here makes the payload correct for every integration rather than
  # betting on which ones learned the newer format.
  #
  # Only fields guaranteed present on "Object Created" are referenced. Pulling
  # optional fields such as object.size or object.etag would cause EventBridge
  # to fail the transformation for events that omit them.
  dynamic "input_transformer" {
    for_each = var.eventbridge_emit_s3_envelope ? [1] : []
    content {
      input_paths = {
        bucket = "$.detail.bucket.name"
        key    = "$.detail.object.key"
        region = "$.region"
        time   = "$.time"
      }

      input_template = <<-EOT
        {"Records":[{"eventVersion":"2.1","eventSource":"aws:s3","awsRegion":"<region>","eventTime":"<time>","eventName":"ObjectCreated:Put","s3":{"s3SchemaVersion":"1.0","bucket":{"name":"<bucket>"},"object":{"key":"<key>"}}}]}
      EOT
    }
  }
}

# ---------------------------------------------------------------------------
# Cross-account role Abstract assumes. One role serves every configuration;
# each Abstract configuration reuses the same role_arn and external_id and is
# distinguished only by its sqs_url.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${var.abstract_aws_account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [local.external_id]
    }
  }
}

data "aws_iam_policy_document" "access" {
  statement {
    sid       = "ListTheBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.bucket_arn]

    # s3:prefix constrains the prefix PARAMETER the caller passes, not which
    # keys are returned. Conditioning on it therefore breaks any list call that
    # passes no prefix - including a plain "can this role see the bucket"
    # connectivity check - while GetObject and SQS keep working, which is a
    # miserable partial failure to diagnose. Off by default; GetObject below is
    # always prefix-scoped and that is the real confidentiality boundary.
    dynamic "condition" {
      for_each = var.scope_list_bucket_to_prefixes ? [1] : []
      content {
        test     = "StringLike"
        variable = "s3:prefix"
        values   = [for k, v in var.sources : "${v.prefix}*"]
      }
    }
  }

  statement {
    sid       = "ReadTheObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [for k, v in var.sources : "${local.bucket_arn}/${v.prefix}*"]
  }

  statement {
    sid    = "ConsumeTheQueues"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
    ]
    resources = local.queue_arns
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "DecryptWithTheCMK"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role" "abstract" {
  name               = var.role_name
  description        = "Assumed by Abstract Security to read ${var.bucket_name} via per-source SQS queues"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = merge(var.tags, { Name = var.role_name })
}

resource "aws_iam_role_policy" "abstract" {
  name   = "AbstractIntegrationAccess"
  role   = aws_iam_role.abstract.id
  policy = data.aws_iam_policy_document.access.json
}

# ---------------------------------------------------------------------------
# A silently-filling dead-letter queue is the failure mode that costs a customer
# a week of data. Alarm on it by default.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  for_each = var.create_dlq_alarms ? var.sources : {}

  alarm_name          = "${local.name}-${each.key}-dlq-not-empty"
  alarm_description   = "Objects from s3://${var.bucket_name}/${each.value.prefix} are failing delivery to the Abstract ${each.key} queue."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq[each.key].name
  }

  alarm_actions = var.dlq_alarm_actions
  ok_actions    = var.dlq_alarm_actions

  tags = merge(var.tags, { AbstractSource = each.key })
}
