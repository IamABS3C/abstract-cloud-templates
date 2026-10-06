# Choose your AWS template

Answer the first question that matches your situation. Each template's own page says what it creates,
what it never touches and what it needs.

**Launch Stack** opens the CloudFormation console with the template already loaded. The button is on
each template's page, here and in the onboarding app. The app also lets you pick the Region.

## 1. Do your logs already land in an S3 bucket that notifies an SQS queue?

| Situation | Use | Launch Stack |
|---|---|---|
| Yes, one source per bucket and queue | [Read role for an existing bucket and queue](../../templates/aws/aws-access-read-role-existing-bucket-and-queue/README.md): builds only the IAM role Abstract assumes | Yes |
| Yes, one security bucket holds several sources under different prefixes | [One queue per source, for a bucket you already have](../../templates/aws/aws-source-existing-bucket-queues/README.md): a queue per prefix, so each source gets its own parser | No: Terraform |

Never point two Abstract integrations at one queue. SQS hands each message to only one reader, so the
two would split the stream at random, with no error.

## 2. Is the source not writing to S3 yet?

One stack builds the bucket, the queue, the role and, where AWS allows it, the logging itself.

| Source | Use | Launch Stack |
|---|---|---|
| CloudTrail (API activity) | [CloudTrail logs](../../templates/aws/aws-source-cloudtrail-s3-sqs/README.md) | Yes |
| VPC Flow Logs | [VPC Flow Logs](../../templates/aws/aws-source-vpc-flow-logs-s3-sqs/README.md) | Yes |
| AWS WAF | [WAF logs](../../templates/aws/aws-source-waf-logs-s3-sqs/README.md) | Yes |
| ALB, NLB or Classic Load Balancer | [Load balancer logs](../../templates/aws/aws-source-load-balancer-logs-s3-sqs/README.md) | Yes |
| CloudFront | [CloudFront logs](../../templates/aws/aws-source-cloudfront-logs-s3-sqs/README.md) | Yes |
| Route 53 Resolver query logs | [Route 53 Resolver logs](../../templates/aws/aws-source-route53-resolver-logs-s3-sqs/README.md) | Yes |
| S3 server access logs | [S3 access logs](../../templates/aws/aws-source-s3-access-logs-s3-sqs/README.md) | Yes |
| Anything else your own shipper writes to S3 | [Generic S3 source](../../templates/aws/aws-source-generic-s3-sqs/README.md) | Yes |

For CloudTrail across a whole organization, deploy the CloudTrail template once in the management account
as an organization trail (`CtIsOrganizationTrail=true`). Don't use the StackSet for it.

## 3. Do you need several of those sources?

| Situation | Use | Launch Stack |
|---|---|---|
| Several sources in one account and Region, with the identity and encryption set once | [Multiple sources](../../templates/aws/aws-source-multiple-sources-one-bucket/README.md): a master stack that nests the per-source stacks; each source still gets its own bucket and queue | Yes |
| The same source in every account of an organizational unit, including accounts added later | [Organization StackSet](../../templates/aws/aws-source-s3-sqs-organization-stackset/README.md): run `deploy.sh` from the management account or a delegated StackSets administrator | No: a command-line wrapper around StackSets |

## 4. Are the logs somewhere other than S3?

| Where the logs are | Use | Launch Stack |
|---|---|---|
| CloudWatch Logs | [CloudWatch Logs by API](../../templates/aws/aws-source-cloudwatch-logs-api/README.md): Abstract reads the log groups directly; for high volume, export to S3 instead | Yes |
| A Kinesis data stream | [Kinesis stream](../../templates/aws/aws-source-kinesis-stream/README.md) | Yes |
| Amazon Security Lake | [Security Lake subscriber](../../templates/aws/aws-source-security-lake/README.md) | Yes |

## The helper

[Log delivery helper](../../templates/aws/aws-foundation-log-delivery-helper/README.md) is a support
stack. It does not send anything to Abstract. Deploy it only when a template needs a lookup CloudFormation
cannot do by name (a KMS alias, a queue name, a web ACL name), or to switch on S3 server access logging or
load balancer access logs for resources you already have.
