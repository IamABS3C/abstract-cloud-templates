variable "routing_mode" {
  type        = string
  description = <<-EOT
    How S3 ObjectCreated events reach the per-source SQS queues.

      "direct"      Pattern A - one S3 bucket notification containing one
                    prefix-filtered QueueConfiguration per source. Fewest moving
                    parts. Requires Terraform to own the bucket notification.

      "sns"         Pattern B - S3 -> one SNS topic -> one SQS queue per source,
                    filtered with a MessageBody filter policy on the object key.
                    Single fan-out origin; extra consumers can be added later.

      "eventbridge" Pattern C - S3 -> EventBridge -> one rule per source -> one
                    SQS queue per source. Richest filtering (any field, not just
                    prefix) and the easiest to extend. Costs per event.

    Every mode produces the same contract: one SQS queue per source, because an
    Abstract S3+SQS configuration is scoped by `sqs_url` and nothing else.
  EOT

  validation {
    condition     = contains(["direct", "sns", "eventbridge"], var.routing_mode)
    error_message = "routing_mode must be one of: direct, sns, eventbridge."
  }
}

variable "eventbridge_emit_s3_envelope" {
  type        = bool
  default     = true
  description = <<-EOT
    Only consulted when routing_mode is "eventbridge".

    An EventBridge S3 event puts bucket and key at detail.bucket.name and
    detail.object.key. A native S3 notification puts them at
    Records[].s3.bucket.name and Records[].s3.object.key. Different shapes.

    Support for the EventBridge shape is PER-INTEGRATION, not platform-wide.
    Evidence: default.vpc_flow had to ADD it in version 1.0.1 - "Support for
    receiving VPC Flow Log notifications via SNS-wrapped messages and AWS
    EventBridge events, in addition to the existing direct S3 event format."
    That it was a named feature addition is the point: integrations without
    that work only understand the direct S3 shape. default.cloudtrail 1.0.6's
    changelog makes no mention of EventBridge, and the Abstract setup doc for
    the generic S3+SQS source documents only S3 -> SQS and S3 -> SNS -> SQS.

    Leaving this true attaches an input transformer that reshapes each event
    into the native S3 envelope, so the queue payload is correct for EVERY
    integration regardless of whether it learned the EventBridge shape. Set it
    to false only for an integration you have confirmed supports EventBridge
    natively, and only if you want the extra EventBridge metadata.

    One thing to test rather than trust. S3 documents that object keys in
    NATIVE notifications are URL-encoded - "red flower.jpg" arrives as
    "red+flower.jpg". AWS documents nothing either way about encoding in the
    EventBridge form, and the evidence is mixed, so this module does not assume
    an answer and neither should you.

    It makes no difference for keys built from ordinary path characters. If
    your keys can contain spaces or other characters requiring encoding, settle
    it empirically before go-live: enable EventBridge on a scratch bucket, copy
    in a file named "a b+c.txt", point a catch-all rule at a CloudWatch Logs
    group, and read the raw detail.object.key. Three minutes, and it turns a
    guess into a fact.
  EOT
}

variable "bucket_name" {
  type        = string
  description = <<-EOT
    Name of the EXISTING S3 bucket holding the security logs. This module never
    creates or deletes the bucket.

    The bucket and the SQS queues must be in the SAME AWS region - an Abstract
    documented requirement. This module creates the queues in the provider's
    region, so point the provider at the bucket's region.
  EOT

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 chars, lowercase)."
  }
}

variable "manage_bucket_notification" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether this module writes to the bucket's notification configuration.
    Honored in EVERY routing mode, including "eventbridge".

    A bucket has exactly ONE notification configuration, so Terraform managing
    it will REPLACE whatever is there today, including notifications belonging
    to other teams. Set to false when you do not own the bucket.

    What false gives you, per mode:
      direct / sns   queues, policies, and the IAM role are built; the
                     notification is not written. Hand the rendered JSON in the
                     `bucket_notification_plan` output to the bucket owner.
      eventbridge    queues, rules, policies, and the IAM role are built; the
                     bucket's EventBridgeConfiguration flag is NOT set, so the
                     bucket emits nothing until someone sets it. The one-line
                     command is in the `manual_bucket_steps` output.

    In "eventbridge" mode with this left true, the module sets only the
    independent EventBridgeConfiguration flag and does not touch
    QueueConfigurations - so it will not disturb another team's notifications
    the way "direct" mode would.
  EOT
}

variable "sources" {
  type = map(object({
    prefix      = string
    suffix      = optional(string, "")
    description = optional(string, "")
    integration = optional(string, "default.aws_s3_sqs_source.1_2_0")
    dataformat  = optional(string, "json")
  }))

  description = <<-EOT
    One entry per log source in the bucket. The map key becomes the queue name
    suffix, so keep it short and DNS-ish (cloudtrail, guardduty, securityhub).

      prefix       Key prefix that isolates this source, e.g. "cloudtrail/".
      suffix       Optional key suffix filter, e.g. ".json.gz".
      description  Free text, surfaced in the outputs to help whoever wires up
                   the Abstract configurations.
      integration  Abstract integration id to bind this queue to. Use the
                   source-specific one where it exists so you inherit the
                   managed parser; fall back to the generic S3+SQS source.
      dataformat   json | nd | parquet | conj. There is deliberately no csv
                   option - the source decodes before the parser runs.

    Example:
      sources = {
        cloudtrail  = { prefix = "AWSLogs/",     suffix = ".json.gz", integration = "default.cloudtrail.1_0_6" }
        guardduty   = { prefix = "guardduty/",   integration = "default.guardduty.1_0_3" }
        securityhub = { prefix = "securityhub/", integration = "default.aws_s3_sqs_source.1_2_0" }
      }
  EOT

  validation {
    condition     = length(var.sources) > 0
    error_message = "Define at least one source."
  }

  validation {
    # SQS queue names accept alphanumerics, hyphens and underscores. The key is
    # concatenated with name_prefix into the queue name, so it is bounded well
    # under the 80-character limit rather than at it.
    condition     = alltrue([for k, v in var.sources : can(regex("^[a-z0-9][a-z0-9_-]{0,38}$", k))])
    error_message = "Source keys must be lowercase alphanumeric with hyphens or underscores, 1-39 chars."
  }

  validation {
    condition     = alltrue([for k, v in var.sources : v.prefix != ""])
    error_message = "Every source needs a non-empty prefix, otherwise it matches the whole bucket and collides with every other source."
  }

  validation {
    # S3's actual rule is narrower than "prefixes must not overlap": overlapping
    # prefixes ARE legal as long as the suffixes do not also overlap. AWS's own
    # example is two rules both on prefix "images", one suffix ".jpg" and one
    # ".png". So only reject when BOTH dimensions collide.
    #
    # Suffix overlap is string containment, not equality - ".jpg" and "jpg"
    # overlap, and an empty suffix matches everything, so it overlaps with any
    # other suffix.
    condition = alltrue([
      for pair in setproduct(keys(var.sources), keys(var.sources)) :
      pair[0] == pair[1] ? true : !(
        (
          startswith(var.sources[pair[0]].prefix, var.sources[pair[1]].prefix) ||
          startswith(var.sources[pair[1]].prefix, var.sources[pair[0]].prefix)
          ) && (
          var.sources[pair[0]].suffix == "" ||
          var.sources[pair[1]].suffix == "" ||
          endswith(var.sources[pair[0]].suffix, var.sources[pair[1]].suffix) ||
          endswith(var.sources[pair[1]].suffix, var.sources[pair[0]].suffix)
        )
      )
    ])
    error_message = <<-EOT
      Two sources collide on BOTH prefix and suffix.

      S3 allows overlapping prefixes when the suffixes do not also overlap - two
      rules on prefix "images/" are fine if one ends ".jpg" and the other
      ".png". These two sources overlap on both, which is the case that breaks.

      In "direct" mode S3 rejects the entire notification configuration with
      "Configuration is ambiguously defined". In "sns" and "eventbridge" mode it
      is accepted and the object is delivered to BOTH queues, so you ingest and
      pay for it twice.

      Fix by narrowing one prefix, or by giving the two sources non-overlapping
      suffixes. Note that an empty suffix matches everything.
    EOT
  }

  validation {
    condition     = alltrue([for k, v in var.sources : contains(["json", "nd", "parquet", "conj"], v.dataformat)])
    error_message = "dataformat must be one of: json, nd, parquet, conj. There is no csv option on aws_s3_sqs_source."
  }
}

variable "abstract_aws_account_id" {
  type        = string
  description = <<-EOT
    The Abstract-managed AWS account that assumes the role this module creates.

    THIS IS PER-TENANT. It is not a published constant and it differs per
    Abstract tenant and environment. Using another tenant's value produces an
    sts:AssumeRole AccessDenied at configuration-validate time.

    Retrieve YOUR tenant's value with an API key for that tenant:
      POST /v1/integrations/permissions/aws/launch-url?download_template=true
  EOT

  validation {
    condition     = can(regex("^[0-9]{12}$", var.abstract_aws_account_id))
    error_message = "abstract_aws_account_id must be exactly 12 digits."
  }
}

variable "external_id" {
  type        = string
  default     = null
  sensitive   = true
  description = "sts:ExternalId for the assume-role trust condition. Leave null to generate a random UUID; read it back from the external_id output."
}

variable "role_name" {
  type        = string
  default     = "AbstractIntegrationRole"
  description = "Name of the cross-account IAM role Abstract assumes."
}

variable "name_prefix" {
  type        = string
  default     = "abstract"
  description = "Prefix for created SQS queues, SNS topic, and EventBridge rules."
}

variable "kms_key_arn" {
  type        = string
  default     = null
  description = <<-EOT
    Optional CMK ARN. Grants the Abstract role kms:Decrypt, and encrypts the
    queues (and the SNS topic in "sns" mode) with this key instead of the
    service-managed key.

    ####################################################################
    # YOU MUST ALSO EDIT THE CMK'S OWN KEY POLICY. THIS MODULE CANNOT. #
    ####################################################################

    Encrypting a queue with a CMK means the PRODUCER - S3, SNS, or EventBridge
    depending on routing_mode - needs kms:GenerateDataKey* and kms:Decrypt in
    the KEY POLICY of that CMK. An IAM policy is not sufficient; the key policy
    is authoritative.

    This module deliberately does not write your key policy, for the same
    reason it will not blindly overwrite a bucket notification: key policies
    are authoritative documents that usually belong to another team, and a
    careless write locks people out of their own key.

    The failure mode if you skip it is nasty and quiet. Terraform applies
    cleanly, the queue policy looks right, and then delivery fails with
    KMS.AccessDeniedException. The message never reaches the queue, so it never
    reaches the dead-letter queue either - the DLQ alarms in this module cannot
    see it. You get an empty queue and no signal.

    Apply the statement from the `required_kms_key_policy_statement` output
    BEFORE go-live, then send a probe object and confirm it arrives.
  EOT
}

variable "scope_list_bucket_to_prefixes" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether to condition s3:ListBucket on an s3:prefix StringLike matching only
    the configured prefixes.

    Default is false, which grants plain s3:ListBucket on the bucket. That
    sounds looser than it is: s3:prefix constrains the prefix PARAMETER a
    caller passes, not which keys come back, so the strict form breaks any
    list call that passes no prefix or a differently-shaped one - including
    the kind of "can this role see the bucket at all" check a connectivity
    test performs. It fails as AccessDenied on listing while GetObject and SQS
    keep working, which is a confusing partial failure to debug.

    The real confidentiality boundary is s3:GetObject, which this module always
    scopes per-prefix. Listing reveals key names, not contents.

    Set true if key names are themselves sensitive and you have confirmed the
    consumer always lists with a matching prefix.
  EOT
}

variable "message_retention_seconds" {
  type        = number
  default     = 345600
  description = "SQS retention for the live queues. 4 days by default; raise toward the 14-day maximum if Abstract may be paused for longer than a weekend."

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600 (14 days)."
  }
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 300
  description = "SQS visibility timeout. Must exceed the time Abstract needs to fetch and parse one object, or the message reappears and is ingested twice."

  validation {
    condition     = var.visibility_timeout_seconds >= 30 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 30 and 43200."
  }
}

variable "dlq_max_receive_count" {
  type        = number
  default     = 5
  description = "Deliveries attempted before a message is moved to the source's dead-letter queue. Without a DLQ a poison object retries until retention expires and then disappears with no trace."

  validation {
    condition     = var.dlq_max_receive_count >= 1 && var.dlq_max_receive_count <= 1000
    error_message = "dlq_max_receive_count must be between 1 and 1000."
  }
}

variable "dlq_alarm_actions" {
  type        = list(string)
  default     = []
  description = "SNS topic ARNs notified when a dead-letter queue becomes non-empty. Empty list creates the alarms with no action, which still shows red in the console but pages nobody."
}

variable "create_dlq_alarms" {
  type        = bool
  default     = true
  description = "Create a CloudWatch alarm per source that fires when its DLQ holds any message."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to every resource this module creates."
}
