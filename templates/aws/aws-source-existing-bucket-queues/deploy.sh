#!/usr/bin/env bash
# Plan the module against terraform.tfvars, then apply the saved plan with --yes.
# Copy terraform.tfvars.example to terraform.tfvars and edit it first (it is never published).
#   ./deploy.sh          # init and plan
#   ./deploy.sh --yes    # init, plan and apply that plan
set -euo pipefail
cd "$(dirname "$0")"
[ -f terraform.tfvars ] || { echo "copy terraform.tfvars.example to terraform.tfvars and edit it" >&2; exit 2; }
terraform -chdir=terraform init -input=false
terraform -chdir=terraform plan -input=false -var-file=../terraform.tfvars -out=abstract.tfplan
if [ "${1:-}" = "--yes" ]; then
  terraform -chdir=terraform apply -input=false abstract.tfplan
fi
