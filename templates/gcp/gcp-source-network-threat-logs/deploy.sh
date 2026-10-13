#!/usr/bin/env bash
# Plan, then apply with --yes. Variables come from terraform.tfvars: the first run copies
# terraform.tfvars.example there and stops, so you can replace every placeholder.
set -euo pipefail
cd "$(dirname "$0")"
# Cloud Shell deletes a session's files when it ends, Terraform state included. A state that lived only
# here would be lost, and the next run would try to create everything again.
if [ "${CLOUD_SHELL:-}" = "true" ] && [ ! -f backend.tf ]; then
  echo "This is Cloud Shell and there is no backend.tf, so the Terraform state would be deleted with the session." >&2
  echo "Create backend.tf first: TUTORIAL.md, the Terraform section, step 1 (Keep the state outside this session)." >&2
  exit 1
fi
if [ ! -f terraform.tfvars ]; then
  cp terraform.tfvars.example terraform.tfvars
  echo "Wrote terraform.tfvars from terraform.tfvars.example. Fill it in, then run ./deploy.sh again." >&2
  exit 1
fi
# A placeholder is <name>, or a whole value in UPPERCASE words joined by "_" (LOGGING_PROJECT_ID, ORG_ID): no real
# project, organization or billing-account ID has that shape, so an unedited file never reaches a plan.
if grep -Eq '^[^#]*<[A-Za-z_]+>' terraform.tfvars \
   || grep -Eq '^[^#]*=[[:space:]]*"[A-Z][A-Z0-9]*(_[A-Z0-9]+)+"[[:space:]]*$' terraform.tfvars; then
  echo "terraform.tfvars still has a placeholder (a <name>, or an UPPERCASE_NAME). Replace it first." >&2
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
