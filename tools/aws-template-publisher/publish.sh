#!/usr/bin/env bash
#
# publish.sh - Validate, (optionally) create the S3 bucket, and upload every
# Abstract Security CloudFormation template so they can be used with the
# "Launch Stack" quick-create buttons and the master nested stack (which
# references its children by https URL).
#
# Usage:
#   tools/aws-template-publisher/publish.sh --bucket <name> [options]
#
# Options:
#   --bucket <name>     Target S3 bucket (required).
#   --prefix <path>     Key prefix inside the bucket (default: abstract).
#   --region <region>   Region for the bucket / upload (default: $AWS_REGION,
#                       else $AWS_DEFAULT_REGION, else us-east-1).
#   --create-bucket     Create the bucket if it does not exist, with versioning,
#                       Block Public Access, and SSE-S3 enabled.
#   --dry-run           Print what would happen; change nothing.
#   --no-validate       Skip cfn-lint validation.
#   -h, --help          Show this help.
#
# Examples:
#   tools/aws-template-publisher/publish.sh --bucket my-cfn-bucket --create-bucket
#   tools/aws-template-publisher/publish.sh --bucket my-cfn-bucket --prefix abstract --region us-west-2
#
# The bucket stays private. CloudFormation reads a nested stack's child templates with
# the deploying identity's own S3 access, so nothing needs to be public. Upload again
# after upgrading: renamed templates are added under their new names, and a stack you
# already deployed keeps working from the old objects, which are left in place.

set -euo pipefail

BUCKET=""
PREFIX="abstract"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
CREATE_BUCKET=false
DRY_RUN=false
VALIDATE=true

die() { echo "ERROR: $*" >&2; exit 1; }
run() { if $DRY_RUN; then echo "+ $*"; else eval "$@"; fi; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bucket)      BUCKET="${2:-}"; shift 2 ;;
    --prefix)      PREFIX="${2:-}"; shift 2 ;;
    --region)      REGION="${2:-}"; shift 2 ;;
    --create-bucket) CREATE_BUCKET=true; shift ;;
    --public-read|--acl-public) die "$1 was removed: templates stay private (CloudFormation reads them with your own access), and new buckets refuse object ACLs." ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --no-validate) VALIDATE=false; shift ;;
    -h|--help)     sed -n '2,40p' "$0"; exit 0 ;;
    *)             die "Unknown option: $1 (use --help)" ;;
  esac
done

[[ -n "$BUCKET" ]] || die "--bucket is required (use --help)."
command -v aws >/dev/null 2>&1 || die "aws CLI not found."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../../templates/aws" && pwd)"
# every CloudFormation template, as <template-id>/template.yaml; uploaded as <template-id>.yaml, the name the
# multi-source template nests
TEMPLATES=("$TEMPLATE_DIR"/aws-*/template.yaml)

echo "==> Region : $REGION"
echo "==> Bucket : s3://${BUCKET}/${PREFIX}/"
$DRY_RUN && echo "==> DRY RUN (no changes will be made)"

# --- validate ---------------------------------------------------------------
if $VALIDATE; then
  if command -v cfn-lint >/dev/null 2>&1; then
    echo "==> Validating templates with cfn-lint..."
    cfn-lint "${TEMPLATES[@]}" && echo "    cfn-lint: 0 errors"
  else
    echo "==> cfn-lint not installed; skipping (pip install cfn-lint to enable)."
  fi
fi

# --- create bucket (optional) ----------------------------------------------
bucket_exists() { aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; }

if bucket_exists; then
  echo "==> Bucket already exists; reusing it."
elif $CREATE_BUCKET; then
  echo "==> Creating bucket ${BUCKET} in ${REGION}..."
  if [[ "$REGION" == "us-east-1" ]]; then
    run "aws s3api create-bucket --bucket '$BUCKET' --region '$REGION'"
  else
    run "aws s3api create-bucket --bucket '$BUCKET' --region '$REGION' \
        --create-bucket-configuration LocationConstraint='$REGION'"
  fi
  echo "==> Enabling versioning, encryption, and Block Public Access..."
  run "aws s3api put-bucket-versioning --bucket '$BUCKET' \
      --versioning-configuration Status=Enabled"
  run "aws s3api put-bucket-encryption --bucket '$BUCKET' \
      --server-side-encryption-configuration \
      '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'"
  run "aws s3api put-public-access-block --bucket '$BUCKET' \
      --public-access-block-configuration \
      BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
else
  die "Bucket ${BUCKET} not found. Re-run with --create-bucket to create it."
fi

# --- upload -----------------------------------------------------------------
echo "==> Uploading templates..."
for f in "${TEMPLATES[@]}"; do
  name="$(basename "$(dirname "$f")").yaml"
  run "aws s3 cp '$f' 's3://${BUCKET}/${PREFIX}/${name}' \
      --region '$REGION' --content-type 'application/x-yaml'"
  echo "    + ${name}"
done

# --- summary ----------------------------------------------------------------
if [[ "$REGION" == "us-east-1" ]]; then
  BASE_URL="https://${BUCKET}.s3.amazonaws.com/${PREFIX}"
else
  BASE_URL="https://${BUCKET}.s3.${REGION}.amazonaws.com/${PREFIX}"
fi

cat <<EOF

==> Done.

TemplateBaseUrl / TEMPLATE_URL:
  ${BASE_URL}

Master nested-stack deploy:
  aws cloudformation deploy \\
    --template-file ${TEMPLATE_DIR}/aws-source-multiple-sources-one-bucket/template.yaml \\
    --stack-name abstract-aws --capabilities CAPABILITY_NAMED_IAM \\
    --region ${REGION} \\
    --parameter-overrides TemplateBaseUrl=${BASE_URL} \\
                          AbstractPrincipalArn=... ExternalId=... \\
                          EnableCloudTrail=true

Quick-create button URL (replace TEMPLATE_URL in the README):
  ${BASE_URL}
EOF

