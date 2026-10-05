# Security model

These templates grant a third party (Abstract Security) read access to log data in your
AWS account. This document explains the trust model and the controls that keep that access
minimal and auditable.

## Trust model

- **Role-based (recommended).** Each template's role trusts *only* the Abstract principal
  you supply and requires a matching `sts:ExternalId`. The External ID prevents the
  [confused-deputy problem](https://docs.aws.amazon.com/IAM/latest/UserGuide/confused-deputy.html):
  even if someone learns the role ARN, they cannot assume it without the secret External ID
  that Abstract presents. Treat the External ID as a credential.
- **Access-key (fallback).** An IAM user with the same scoped read policy. Long-lived
  credentials; use only when role assumption is impossible, and prefer
  `StoreCredentialsInSecretsManager=true` so the secret is never an output.

## Least privilege

- IAM actions are read-only and scoped to the specific bucket, queue, stream, or
  log-group — not `Resource: "*"` (except where an API requires account-wide `Describe`).
- `kms:Decrypt` is granted only on the specific key, only when `SSE-KMS` is selected.
- An optional `PermissionsBoundaryArn` caps the created identity regardless of its policy.

## Data-plane controls

- S3: Block Public Access (all four), ACLs disabled (`BucketOwnerEnforced`), HTTPS-only
  bucket policy (`aws:SecureTransport` deny), versioning, lifecycle expiry, and
  `DeletionPolicy: Retain`.
- Bucket/queue/topic policies restrict writers to the correct service principal plus
  `aws:SourceAccount` (and optionally `aws:SourceArn`).
- SQS/SNS encryption on by default; dead-letter queue with redrive on every created queue.
- KMS keys have rotation enabled and a tightly-scoped key policy.

## Handling secrets

- `ExternalId` and `SecretAccessKey` are `NoEcho`. The External ID is never echoed in
  outputs. The secret access key appears in outputs **only** when
  `StoreCredentialsInSecretsManager=false`; anyone with `cloudformation:DescribeStacks` can
  read stack outputs, so prefer the Secrets Manager option for production and restrict
  `describe-stacks`.
- Rotate access keys after onboarding; prefer role-based auth.

## Reporting a concern

Email **security@abstract.security** with details and reproduction steps. Please do not
open public issues for security-sensitive reports.
