#!/usr/bin/env bash
#
# discover.sh - Look up existing AWS resources that the Abstract templates can
# reference (buckets, SQS queues, KMS keys, IAM roles, Kinesis streams,
# CloudWatch log groups, VPCs/subnets, WAF WebACLs, CloudTrail trails, and
# Security Lake data lakes) - in one region or across all regions.
#
# CloudFormation cannot natively render a dropdown of arbitrary live resources
# (it only does so for SSM and a fixed set of EC2 types), so this script is the
# "lookup" companion: run it, copy the value you want, and paste it into the
# stack parameter (or feed it to scripts/deploy.sh).
#
# Usage:
#   scripts/discover.sh [options] [resource ...]
#
# Options:
#   --region <region>   Region to query (default: configured region).
#   --all-regions       Query every enabled region (slower).
#   --profile <name>    AWS CLI profile to use.
#   -h, --help          Show this help.
#
# Resources (default: all): buckets queues keys roles streams loggroups
#                           vpcs subnets webacls trails securitylake
#
# Examples:
#   scripts/discover.sh                       # everything, current region
#   scripts/discover.sh --region us-west-2 buckets queues keys
#   scripts/discover.sh --all-regions streams loggroups

set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
ALL_REGIONS=false
PROFILE_ARG=""
RESOURCES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region)      REGION="${2:-}"; shift 2 ;;
    --all-regions) ALL_REGIONS=true; shift ;;
    --profile)     PROFILE_ARG="--profile ${2:-}"; shift 2 ;;
    -h|--help)     sed -n '2,33p' "$0"; exit 0 ;;
    -*)            echo "Unknown option: $1" >&2; exit 1 ;;
    *)             RESOURCES+=("$1"); shift ;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found." >&2; exit 1; }
[[ ${#RESOURCES[@]} -eq 0 ]] && RESOURCES=(buckets queues keys roles streams loggroups vpcs subnets webacls trails securitylake)

# shellcheck disable=SC2086
awsq() { aws $PROFILE_ARG --region "$1" "${@:2}" 2>/dev/null || true; }

hdr() { printf '\n\033[1m== %s ==\033[0m\n' "$1"; }
sub() { printf '\033[36m-- %s [%s]\033[0m\n' "$1" "$2"; }

want() { for r in "${RESOURCES[@]}"; do [[ "$r" == "$1" ]] && return 0; done; return 1; }

discover_region() {
  local rgn="$1"

  if want buckets; then
    sub "S3 buckets (global; shown once)" "$rgn"
    # Buckets are global; only print on the first region pass.
    awsq "$rgn" s3api list-buckets --query 'Buckets[].Name' --output text | tr '\t' '\n'
  fi

  want queues && { sub "SQS queues" "$rgn"; awsq "$rgn" sqs list-queues --query 'QueueUrls' --output text | tr '\t' '\n'; }

  if want keys; then
    sub "KMS keys / aliases" "$rgn"
    awsq "$rgn" kms list-aliases \
      --query "Aliases[?starts_with(AliasName,'alias/aws/')==\`false\`].[AliasName,TargetKeyId]" \
      --output text
  fi

  want roles && { sub "IAM roles (global; shown once)" "$rgn"; awsq "$rgn" iam list-roles --query 'Roles[].[RoleName,Arn]' --output text; }

  want streams && { sub "Kinesis streams" "$rgn"; awsq "$rgn" kinesis list-streams --query 'StreamNames' --output text | tr '\t' '\n'; }

  want loggroups && { sub "CloudWatch log groups" "$rgn"; awsq "$rgn" logs describe-log-groups --query 'logGroups[].logGroupName' --output text | tr '\t' '\n'; }

  want vpcs && { sub "VPCs" "$rgn"; awsq "$rgn" ec2 describe-vpcs --query 'Vpcs[].[VpcId,CidrBlock]' --output text; }

  want subnets && { sub "Subnets" "$rgn"; awsq "$rgn" ec2 describe-subnets --query 'Subnets[].[SubnetId,VpcId,CidrBlock]' --output text; }

  if want webacls; then
    sub "WAFv2 WebACLs (REGIONAL)" "$rgn"
    awsq "$rgn" wafv2 list-web-acls --scope REGIONAL --query 'WebACLs[].[Name,ARN]' --output text
    if [[ "$rgn" == "us-east-1" ]]; then
      sub "WAFv2 WebACLs (CLOUDFRONT)" "global"
      awsq us-east-1 wafv2 list-web-acls --scope CLOUDFRONT --query 'WebACLs[].[Name,ARN]' --output text
    fi
  fi

  want trails && { sub "CloudTrail trails" "$rgn"; awsq "$rgn" cloudtrail list-trails --query 'Trails[].[Name,TrailARN]' --output text; }

  want securitylake && { sub "Security Lake data lakes" "$rgn"; awsq "$rgn" securitylake list-data-lakes --query 'dataLakes[].[region,dataLakeArn]' --output text; }
}

ACCOUNT="$(aws $PROFILE_ARG sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")"
echo "Account: $ACCOUNT"

if $ALL_REGIONS; then
  BASE_REGION="${REGION:-us-east-1}"
  REGIONS="$(awsq "$BASE_REGION" ec2 describe-regions --query 'Regions[].RegionName' --output text)"
  [[ -z "$REGIONS" ]] && REGIONS="us-east-1"
  for rgn in $REGIONS; do
    hdr "REGION: $rgn"
    discover_region "$rgn"
  done
else
  [[ -n "$REGION" ]] || { echo "No region set. Use --region or configure one." >&2; exit 1; }
  hdr "REGION: $REGION"
  discover_region "$REGION"
fi

echo
echo "Tip: pipe to grep, e.g.  scripts/discover.sh buckets | grep waf"
