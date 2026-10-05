# Log delivery lookup helper

<!-- Generated from template.yml by `python -m tools.templates generate`. Do not edit. -->

A Lambda-backed custom resource that does at deploy time what plain CloudFormation cannot: resolve a KMS alias, a queue name, a stream or a web ACL to its ARN, validate a bucket, check a log group, and optionally switch on S3 server access logging or load balancer access logs. Other stacks call it through its exported ServiceToken.

**Cloud:** aws · **Role:** foundation · **Scope:** account

## When to use

A deploy needs a value CloudFormation cannot look up by name (a KMS alias, a queue name, a web ACL name), or needs S3 access logging or load balancer access logs switched on.

## Deploy

From a shell, in this folder:

```bash
./deploy.sh
```

## Prerequisites

- AWS CLI v2, authenticated, and jq for deploy.sh

## Parameters

| Name | Type | Required | Description | Find it |
|---|---|---|---|---|
| `Operation` | string | no | None just deploys the reusable function (export ServiceToken). The Resolve*/ Validate*/Check* operations look something up and return it in the outputs. Enable* operations wire a producer (write). |  |
| `AllowProducerWiring` | string | no | Attach the write permissions (S3 PutBucketLogging, ELB ModifyLoadBalancerAttributes) so the exported function can perform Enable* operations later. Auto-on when Operation is an Enable* operation. |  |
| `KmsAlias` | string | no | KMS alias to resolve (e.g. alias/my-key) for ResolveKmsKey. Find it with: aws kms list-aliases | `aws kms list-aliases` |
| `QueueName` | string | no | SQS queue NAME to resolve to URL+ARN for ResolveQueue. Find it with: aws sqs list-queues | `aws sqs list-queues` |
| `BucketName` | string | no | S3 bucket to validate exists (ValidateBucket). Find it with: aws s3 ls | `aws s3 ls` |
| `StreamName` | string | no | Kinesis stream name to resolve to ARN (ResolveStream). Find it with: aws kinesis list-streams | `aws kinesis list-streams` |
| `WebAclName` | string | no | WAF WebACL name to resolve to ARN (ResolveWebAcl). Find it with: aws wafv2 list-web-acls --scope REGIONAL | `aws wafv2 list-web-acls --scope REGIONAL` |
| `WebAclScope` | string | no | Scope for ResolveWebAcl (CLOUDFRONT must run in us-east-1). |  |
| `LogGroupName` | string | no | CloudWatch log group to check exists (CheckLogGroup). Find it with: aws logs describe-log-groups --query logGroups[].logGroupName | `aws logs describe-log-groups --query logGroups[].logGroupName` |
| `SourceBucketName` | string | no | S3 bucket to enable server-access logging ON (EnableS3SourceLogging). Find it with: aws s3 ls | `aws s3 ls` |
| `TargetBucketName` | string | no | Destination log bucket for EnableS3SourceLogging / EnableAlbAccessLogs. Find it with: aws s3 ls | `aws s3 ls` |
| `TargetPrefix` | string | no | Key prefix in the destination bucket. |  |
| `LoadBalancerArn` | string | no | ARN of the ALB/NLB to enable access logs on (EnableAlbAccessLogs). Find it with: aws elbv2 describe-load-balancers --query LoadBalancers[].LoadBalancerArn | `aws elbv2 describe-load-balancers --query LoadBalancers[].LoadBalancerArn` |
| `LogRetentionDays` | int | no | Retention, in days, of the helper function's CloudWatch log group. |  |
| `FunctionTimeout` | int | no | Timeout of the helper Lambda function, in seconds. |  |

## Permissions

- **Create IAM roles, Lambda functions and CloudWatch log groups** on The target AWS account: Deployer: the stack creates the helper function and its execution role.
- **Read-only describe and list calls (KMS, SQS, S3, Kinesis, WAFv2, CloudWatch Logs)** on The helper's execution role: Helper: resolve names to ARNs and validate resources.
- **s3:PutBucketLogging, elasticloadbalancing:ModifyLoadBalancerAttributes** on The helper's execution role, only with AllowProducerWiring=true or an Enable* operation: Helper: switch on producer logging when asked to.

## Creates

- A Lambda function &lt;stack-name&gt;-helper with inline Python source, and its CloudWatch log group
- The function's execution role: read-only lookups, plus write permissions only when producer wiring is allowed
- One custom-resource invocation when Operation is not None, whose result is a stack output
- An export &lt;stack-name&gt;-ServiceToken other stacks use to call the helper

## Never touches

- Any resource it only resolves or validates: lookups are read-only
- Producer settings, unless Operation is EnableS3SourceLogging or EnableAlbAccessLogs, or AllowProducerWiring=true

## Outputs

- `ServiceToken`
- `KmsKeyArn`
- `QueueUrl`
- `QueueArn`
- `ValidatedBucket`
- `StreamArn`
- `WebAclArn`

## Verify

| Check | Command | Healthy when |
|---|---|---|
| The helper exported its service token | `aws cloudformation describe-stacks --stack-name <stack-name> --query 'Stacks[0].Outputs' --output table` | ServiceToken is present, and the output for the chosen Operation holds the resolved value. |
