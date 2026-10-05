<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Cold archive and replay

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

A **second** sink writing to Cloud Storage. A sink has exactly one destination, so this
cannot be an extra destination on the streaming sink.

<walkthrough-info-message>**Not the detection path.** GCS batches, so latency becomes
minutes to hours. Keep Pub/Sub for anything you alert on, and use this for evidence and
backfill.</walkthrough-info-message>

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Step 1 — Take the filter from the streaming deployment

```bash
cd ../gcp-source-audit-logs-organization && terraform output -raw effective_filter
cd ../gcp-archive-log-bucket
```

Use that **exact string**. An archive that quietly captures less than the stream is worse
than no archive, because you will trust it during an investigation.

## Step 2 — Decide retention, carefully

```hcl
archive_retention_days = 365
```

A retention **lock** is what makes this evidentiary rather than a copy. It also means
objects **cannot be deleted before it expires — including by you, including by mistake,
including if you put the wrong logs in.** Set it deliberately or leave it at 0.

## Step 3 — Plan, then apply

```bash
cat > terraform.tfvars <<EOF
org_id              = "YOUR_ORG_ID"
log_project         = "YOUR_LOG_PROJECT"
archive_bucket_name = "acme-abstract-log-archive"
filter              = "PASTE_THE_FILTER_FROM_STEP_1"
EOF
terraform init && terraform plan
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

The archive sink has its **own** writer identity, distinct from the streaming sink's, and
it gets its own grant. If the bucket stays empty, that binding is where to look.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
