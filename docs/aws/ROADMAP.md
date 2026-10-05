# Roadmap & recommendations

Status of planned enhancements. Most near-term items are now **implemented and wired in**;
remaining items are noted with their rationale.

## Implemented ✅

- **Lambda-backed lookup/resolve helper** — `aws-foundation-log-delivery-helper`.
  A custom-resource Lambda resolves a KMS alias / SQS queue name / Kinesis stream name / WAF
  WebACL name to its ARN, validates an S3 bucket / log group exists, and can wire producers
  (S3 source-bucket logging, ALB access logs). Deploy standalone to perform one operation and
  read the resolved value from outputs, or reuse the exported `ServiceToken` from other stacks
  via `Custom::AbstractHelper`. *(Note: this is deploy-time lookup/resolution — see "Console
  dropdowns" below for the one thing it can't change.)*
- **Observability** — optional CloudWatch **DLQ alarm**, **queue-age alarm**, **dashboard**,
  and an **alarm SNS topic + email** on every S3+SQS source (`EnableDlqAlarm`,
  `EnableQueueAgeAlarm`, `EnableDashboard`, `AlarmEmail`), also exposed through the master
  stack.
- **StackSets rollout** — `aws-source-s3-sqs-organization-stackset` for SERVICE_MANAGED
  org/multi-region deployment, plus docs in [DEPLOYMENT.md](DEPLOYMENT.md).
- **GitHub Actions CI** — `.github/workflows/ci.yml` runs
  `cfn-lint`, `shellcheck`, and compiles the embedded Lambda on every push/PR.
- **Example parameter files** — each template's `examples/` folder and `parameters.example.json`.
- **SSM export** — `ExportToSsm` publishes non-secret outputs to Parameter Store so other
  stacks/regions/tooling can look them up.
- **Resource discovery + guided deploy** — `discover.sh`
  (any region / all regions). The interactive guided `deploy.sh` is retired; each template now
  ships its own `deploy.sh` (change-set preview, `--yes` to apply).
- **Auto-create hosting bucket** — `publish.sh --create-bucket`.
- **Partition-aware** — every ARN uses `${AWS::Partition}`/`${AWS::Region}`, so the templates
  are GovCloud (`aws-us-gov`) / China (`aws-cn`) ready (verify service availability and the
  Abstract principal per partition before relying on it).

## Console dropdowns — the one hard platform limit

CloudFormation renders **live** create-stack dropdowns only for SSM parameters and a fixed set
of EC2-class types; a macro runs *after* parameters are entered, so it cannot add dropdowns
either. There is therefore no way to make the console show a live list of S3 buckets, KMS
keys, IAM roles, SQS queues, Kinesis streams, or log groups. The repo covers this with:
**(1)** every enumerable setting as an `AllowedValues` native dropdown; **(2)** `discover.sh`
+ interactive `deploy.sh` for live existing-resource selection; **(3)** the helper Lambda for
deploy-time resolve/validate. This is the same trade-off AWS's own solution templates make.

## Remaining / future

- **CloudFront producer wiring.** The helper does S3 source-bucket logging and ALB access
  logs; enabling CloudFront standard logging on an *existing* distribution needs a full
  `update-distribution` config round-trip and is deferred (higher risk). Point the
  distribution at the bucket manually for now.
- **EventBridge → Slack/PagerDuty.** Today alarms publish to SNS (email-subscribable); a
  ready-made EventBridge rule + chatbot integration could be added.
- **Cost guardrails.** An optional AWS Budgets alarm when CloudTrail data events / high-volume
  flow logs are enabled.
- **More Security Lake sources as first-class master toggles** (currently one `SourceName`
  per Security Lake child).
- **OCSF normalization notes** per source for downstream analytics.

## Recommendations (apply today)

- Prefer **`AuthMode=AssumeRole`**; reserve access keys for non-AWS Abstract and pair with
  `StoreCredentialsInSecretsManager=true` + rotation.
- Use **`SSE-KMS` + `KmsMode=CreateNew`** for regulated data.
- Keep **CloudTrail data events off** unless needed (cost/volume).
- Turn on **`EnableDlqAlarm=true`** in production so processing failures page you.
- Turn on **`ExportToSsm=true`** for cross-stack discovery.
- Use **StackSets** + an **organization trail** for org-wide coverage.

Have a request? Open an issue with the source, the AWS service principal, and the log format;
new S3+SQS sources are usually a one-line addition to the `SourceConfig` mapping.
