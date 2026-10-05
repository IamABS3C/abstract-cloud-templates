# Deployment guide

Step-by-step for every deployment method, plus region/resource selection, StackSets, and
troubleshooting.

## Prerequisites

- AWS CLI v2, authenticated (`aws sts get-caller-identity` works).
- Permission to create IAM roles/users, S3, SQS, SNS, KMS, and the producer resources.
- (Optional) `cfn-lint` for local validation: `pip install cfn-lint`.
- From Abstract: the **principal ARN/account ID** and the **External ID** for the source.

---

## Method 1 — The template's own deploy.sh (recommended first run)

Every template is a folder under `templates/aws/<template-id>/` with a `deploy.sh` and a
`parameters.example.json`. Copy the parameters file, edit it, then preview and apply:

```bash
cd templates/aws/aws-source-cloudtrail-s3-sqs
./deploy.sh abstract-cloudtrail AbstractPrincipalArn=111122223333 ExternalId=SECRET   # change set, nothing applied
./deploy.sh abstract-cloudtrail AbstractPrincipalArn=111122223333 ExternalId=SECRET --yes
```

---

## Method 2 — Direct CLI

```bash
aws cloudformation deploy \
  --template-file templates/aws/aws-source-vpc-flow-logs-s3-sqs/template.yaml \
  --stack-name abstract-vpcflow --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
      AuthMode=AssumeRole \
      AbstractPrincipalArn=111122223333 ExternalId=SECRET \
      VpcFlowResourceId=vpc-0abc123 VpcFlowTrafficType=ALL \
      BucketEncryption=SSE-KMS QueueEncryption=SSE-KMS KmsMode=CreateNew \
      ExportToSsm=true
```

Read outputs:

```bash
aws cloudformation describe-stacks --stack-name abstract-vpcflow \
  --query 'Stacks[0].Outputs' --output table
```

---

## Method 3 — Console (Launch Stack)

1. Publish the templates (Method 5 below) and note the base URL. CloudFormation only loads a
   template from an S3 https URL; a GitHub raw URL is refused.
2. Open the quick-create URL for the template with `templateURL` set to its S3 object.
3. The console shows grouped, labeled parameters; enumerated ones are dropdowns. Fill the
   identity fields, choose modes, and deploy.

---

## Method 4 — Nested stack (many sources at once)

```bash
cd templates/aws/aws-source-multiple-sources-one-bucket
./deploy.sh abstract-aws my-cfn-bucket \
    AbstractPrincipalArn=111122223333 ExternalId=SECRET \
    EnableCloudTrail=true EnableVPCFlowLogs=true EnableWAF=true \
    VpcFlowResourceId=vpc-0abc123 \
    WafWebAclArn=arn:aws:wafv2:us-east-1:111122223333:regional/webacl/x/abc --yes
```

`deploy.sh` uploads the per-source templates this stack nests to the bucket, then deploys the
stack with `TemplateBaseUrl` pointing at them. Shared identity, encryption and `ExportToSsm`
flow down to every enabled child.

---

## Method 5 — Publish templates for hosting

```bash
tools/aws-template-publisher/publish.sh --bucket my-cfn-bucket --create-bucket           # create + upload
tools/aws-template-publisher/publish.sh --bucket my-cfn-bucket --region us-west-2        # existing bucket
tools/aws-template-publisher/publish.sh --bucket my-cfn-bucket --create-bucket --dry-run # preview
```

Each template is uploaded as `<template-id>.yaml`.

---

## Choosing the region

CloudFormation deploys to **one region per stack**. Set it with `--region` (scripts & CLI),
`AWS_REGION`, or the console region selector. To cover multiple regions, repeat the deploy or
use StackSets (below). Templates contain no hard-coded region — every ARN derives from
`${AWS::Region}`/`${AWS::Partition}`.

## Resource selection (existing vs. new)

```bash
# 1) Discover what already exists
tools/aws-template-publisher/discover.sh --region us-east-1 buckets queues keys
tools/aws-template-publisher/discover.sh --all-regions streams loggroups

# 2) Reference it
... BucketMode=UseExisting BucketName=my-existing-logs \
    QueueMode=UseExisting ExistingQueueArn=arn:aws:sqs:... ExistingQueueUrl=https://sqs... \
    KmsMode=UseExisting ExistingKmsKeyArn=arn:aws:kms:...
```

**Why no native dropdown for buckets/keys/queues/streams/log groups?** CloudFormation only
offers live dropdowns for SSM parameters and a fixed set of EC2-class types. Forcing an
AWS-specific type would make the parameter *mandatory and non-blank*, which breaks the
universal multi-source template (most of those params are only relevant for one source). So
the repo provides `discover.sh` (list) instead, and
`ExportToSsm` so a stack's outputs become SSM-referenceable. A future **Lambda-backed lookup
macro** (see [ROADMAP.md](ROADMAP.md)) can add true in-console live dropdowns; it's opt-in
because it adds a Lambda + permissions and complicates quick-create.

## Looking up / resolving / wiring with the helper

Deploy `aws-foundation-log-delivery-helper` to resolve a name to an ARN
or validate a resource at deploy time, and read the result from the outputs:

```bash
# Resolve a KMS alias -> key ARN
aws cloudformation deploy --template-file templates/aws/aws-foundation-log-delivery-helper/template.yaml \
  --stack-name abstract-helper-kms --capabilities CAPABILITY_IAM \
  --parameter-overrides Operation=ResolveKmsKey KmsAlias=alias/my-logs-key
aws cloudformation describe-stacks --stack-name abstract-helper-kms \
  --query 'Stacks[0].Outputs' --output table        # -> KmsKeyArn

# Validate a bucket exists; resolve a queue name -> URL+ARN; resolve a WebACL -> ARN
... Operation=ValidateBucket BucketName=my-logs
... Operation=ResolveQueue   QueueName=my-queue
... Operation=ResolveWebAcl  WebAclName=my-acl WebAclScope=REGIONAL

# Wire a producer (write): enable ALB access logs / S3 source-bucket logging
... Operation=EnableAlbAccessLogs LoadBalancerArn=arn:aws:elasticloadbalancing:... \
    TargetBucketName=my-alb-logs TargetPrefix=alb/
... Operation=EnableS3SourceLogging SourceBucketName=app-bucket \
    TargetBucketName=my-access-logs TargetPrefix=app/
```

Deploy it once with `Operation=None` to keep the reusable function and reference its exported
`ServiceToken` from other stacks as a `Custom::AbstractHelper` resource.

## Multi-region / multi-account with StackSets

Use the StackSet template's `deploy.sh` for the common case; it wraps `scripts/stackset.sh` around a
per-source template and takes that template's `parameters.example.json` as the stack-set parameters:

```bash
cd templates/aws/aws-source-s3-sqs-organization-stackset
./deploy.sh aws-source-cloudtrail-s3-sqs ou-xxxx-xxxxxxxx "us-east-1 us-west-2 eu-west-1" --auto-deploy --dry-run
```

Or by hand:

```bash
aws cloudformation create-stack-set \
  --stack-set-name abstract-cloudtrail \
  --template-body file://templates/aws/aws-source-cloudtrail-s3-sqs/template.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameters ParameterKey=AbstractPrincipalArn,ParameterValue=111122223333 \
               ParameterKey=ExternalId,ParameterValue=SECRET \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false

aws cloudformation create-stack-instances \
  --stack-set-name abstract-cloudtrail \
  --deployment-targets OrganizationalUnitIds=ou-xxxx-xxxxxxxx \
  --regions us-east-1 us-west-2 eu-west-1
```

For org-wide CloudTrail prefer a single **organization trail** (`CtIsOrganizationTrail=true`
+ `CtOrganizationId=o-xxxx`) in the management account over per-account trails.

---

## Updating & deleting

```bash
# Update = re-run deploy with changed parameters (creates a change set automatically)
aws cloudformation deploy --template-file templates/aws/aws-source-cloudtrail-s3-sqs/template.yaml \
  --stack-name abstract-cloudtrail --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ... CtIncludeS3DataEvents=true

# Delete (the log bucket is RETAINED by design; empty + remove it manually if desired)
aws cloudformation delete-stack --stack-name abstract-cloudtrail
```

---

## Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| `Requires capabilities: [CAPABILITY_NAMED_IAM]` | Add `--capabilities CAPABILITY_NAMED_IAM`. |
| Bucket policy `CREATE_FAILED` | Check `SourceArnCondition`/`RestrictBySourceAccount`; WAF buckets must start with `aws-waf-logs-`. |
| CloudTrail fails creating with SNS | Use the `aws-source-cloudtrail-s3-sqs` template, which delivers trail to SNS to SQS. |
| `Multi-Region trail must include global service events` | The template forces `IncludeGlobalServiceEvents=true` for multi-region trails and a Rule blocks the invalid combo — pull the latest template if you hit this. To run a single-region trail with global events off, set `CtIsMultiRegion=false CtIncludeGlobalServiceEvents=false`. |
| `Insights` not generating / rejected | Insights need management events: set `CtIncludeManagementEvents=true` (a Rule enforces this). |
| Org trail fails | Run in the management/delegated account, enable trusted access, set `CtOrganizationId`. |
| No SQS messages | Existing bucket can't be wired by the stack — configure notifications yourself or use `CreateNew`; inspect the DLQ. |
| Abstract read errors | Verify `RoleArn`/`ExternalId`; for `SSE-KMS`, confirm the key grant and that Abstract's role has `kms:Decrypt`. |
| Quick-create 404 | Republish; ensure `TEMPLATE_URL` is replaced and objects are readable. |
| `nested stack` `TemplateURL` invalid | `TemplateBaseUrl` must be an https S3 URL with no trailing slash and the children uploaded. |

Validate locally any time:

```bash
python -m tools.templates lint      # cfn-lint, cfn-guard and the rest, per template
```
