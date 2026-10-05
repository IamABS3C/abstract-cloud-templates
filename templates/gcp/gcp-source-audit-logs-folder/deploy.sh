#!/usr/bin/env bash
# Plan, then apply with --yes. Variables come from terraform.tfvars: the first run copies
# terraform.tfvars.example there and stops, so you can fill in every <placeholder>.
set -euo pipefail
cd "$(dirname "$0")"
if [ ! -f terraform.tfvars ]; then
  cp terraform.tfvars.example terraform.tfvars
  echo "Wrote terraform.tfvars from terraform.tfvars.example. Fill it in, then run ./deploy.sh again." >&2
  exit 1
fi
if grep -Eq '^[^#]*<[A-Za-z_]+>' terraform.tfvars; then
  echo "terraform.tfvars still has a <placeholder>. Fill it in first." >&2
  exit 1
fi
plan="$(mktemp -d)/abstract.tfplan"
terraform init -input=false
terraform plan -input=false -out="$plan"
if [ "${1:-}" = "--yes" ]; then
  terraform apply -input=false "$plan"
else
  echo "Plan only. Run ./deploy.sh --yes to apply it."
fi
