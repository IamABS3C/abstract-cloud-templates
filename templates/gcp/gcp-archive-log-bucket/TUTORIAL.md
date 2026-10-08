<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Cold archive and replay

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

A **second** sink writing to Cloud Storage. A sink has exactly one destination, so this
cannot be an extra destination on the streaming sink.

<walkthrough-info-message>**Not the detection path.** GCS batches, so latency becomes
minutes to hours. Keep Pub/Sub for anything you alert on, and use this for evidence and
backfill.</walkthrough-info-message>

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in, then give the scripts and Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```
<!-- /abstract:signin -->

<!-- abstract:check -->
## Check first

Read-only: nothing changes. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script steps 1 and 2 of the guided setup record your scope and check the rights the sink needs; script step 3 checks the logging project, and the organization policy that can block the service-account key.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/audit-gcp-estate.sh
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

If a permission row shows ✗, find the person who holds that role before you go on.

The guided setup saves your answers (organization, scope, logging project, topic, subscription). Load them for the commands on this page:

```bash
source ~/.abstract-gcp-setup.env
```
<!-- /abstract:check -->

## Take the filter from the streaming deployment

```bash
cd ../gcp-source-audit-logs-organization && terraform output -raw effective_filter
cd ../gcp-archive-log-bucket
```

Use that **exact string**. An archive that quietly captures less than the stream is worse
than no archive, because you will trust it during an investigation.

Set it as `filter` in terraform.tfvars, along with `archive_bucket_name` (for example
`acme-abstract-log-archive`).

## Decide retention, carefully

```hcl
archive_retention_days = 365
```

A retention **lock** is what makes this evidentiary rather than a copy. It also means
objects **cannot be deleted before it expires — including by you, including by mistake,
including if you put the wrong logs in.** Set it deliberately or leave it at 0.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

The archive sink has its **own** writer identity, distinct from the streaming sink's, and
it gets its own grant. If the bucket stays empty, that binding is where to look.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then, with the same `backend.tf`:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
terraform destroy
```
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
source ~/.abstract-gcp-setup.env 2>/dev/null   # the guided setup's saved answers, if you ran it
echo "Logging project: ${LOG_PROJECT:?not set: run export LOG_PROJECT=<your-logging-project-id> first}"
export STATE_PROJECT="${STATE_PROJECT:-$LOG_PROJECT}" STATE_BUCKET="$LOG_PROJECT-abstract-tfstate"
gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$STATE_BUCKET" --project="$STATE_PROJECT" --location=US --uniform-bucket-level-access
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
sed "s/acme-abstract-tfstate/$STATE_BUCKET/" backend.tf.example > backend.tf
```

**2. Fill in your values.** Every value is explained in the file and in this template's README:

```bash
cp terraform.tfvars.example terraform.tfvars
cloudshell edit terraform.tfvars
```

**3. Preview, then apply exactly what you previewed:**

```bash
terraform init
terraform plan -out=abstract.tfplan
terraform apply abstract.tfplan
```

**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`.
<!-- /abstract:terraform -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
