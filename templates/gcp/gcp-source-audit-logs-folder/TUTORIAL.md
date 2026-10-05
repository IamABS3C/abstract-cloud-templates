<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Folder-scope log export

<!-- guided-step -->
> **This is step 4 of the guided setup (Log pipeline).** The guided setup does it for you and checks it: from the repository root run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4`, or follow `tools/gcp-guided-setup/WALKTHROUGH.md`. This page is the Terraform way to do the same step.
<!-- /guided-step -->

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

Same containment guarantee as organization scope, one ring in: **every project in this
folder and every sub-folder, current and future.**

Use this when org-scope IAM has not been granted yet — and note what it costs you: any
project *outside* this folder is silently missed. That is a real gap, not a rounding error.

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Step 1 — Find the folder

```bash
gcloud resource-manager folders list --organization=YOUR_ORG_ID
```

## Step 2 — Preflight

```bash
../../../tools/gcp-guided-setup/preflight.sh --project YOUR_LOG_PROJECT --folder-id YOUR_FOLDER_ID
```

You need `roles/logging.configWriter` **at the folder**.

## Step 3 — Plan, then apply

```bash
cat > terraform.tfvars <<EOF
folder_id   = "YOUR_FOLDER_ID"
log_project = "YOUR_LOG_PROJECT"
EOF
terraform init && terraform plan
```

Read `effective_filter` and `volume_profile` before applying.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**When org scope becomes available, move to `gcp-source-audit-logs-organization`** rather than adding more
folder sinks. Several folder sinks is the shape this design exists to avoid.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
