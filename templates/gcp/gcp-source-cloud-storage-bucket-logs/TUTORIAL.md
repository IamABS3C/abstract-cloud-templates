<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Logs already sitting in a bucket

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

For vendor exports, third-party appliances, or an existing pipeline that already writes
objects into Cloud Storage.

```
bucket → OBJECT_FINALIZE notification → Pub/Sub → Abstract fetches the object
```

<walkthrough-info-message>**If the logs are Google's own, use `gcp-source-audit-logs-organization` instead.**
An aggregated sink is strictly better than watching buckets: one deployment, no
per-bucket wiring, and it covers resources created later.</walkthrough-info-message>

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

## Get a real sample object first

```bash
gsutil ls -l gs://YOUR_BUCKET/** | head
gsutil cp gs://YOUR_BUCKET/some/object.gz /tmp/ && file /tmp/object.gz
```

Do this **first**. Every failure on this path traces back to a format assumption —
compression and wrapper shapes have broken it before. *"It's JSON"* is not a sample.

## List existing notification configs

```bash
gsutil notification list gs://YOUR_BUCKET
```

Adding a config **adds** to what is there; it does not replace. But you still want to know
whether something else is already consuming this bucket.

## Set the bucket variables

Set these in terraform.tfvars:

```hcl
buckets            = ["YOUR_BUCKET"]
bucket_project     = "PROJECT_OWNING_THE_BUCKET"
object_name_prefix = "logs/"
```

Scope `object_name_prefix` — an unscoped config notifies on every object written, and you
pay to fetch each one.

If the bucket is CMEK-encrypted, set `cmek_crypto_key_id` — otherwise every fetch fails
with an error that blames Storage rather than KMS, and sends you down the wrong path.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

### The two permissions people miss

```bash
terraform output gcs_service_agents
```

**The GCS service agent publishes, not you** — and there is one PER OWNING PROJECT, which is why this output is a map. Without `roles/pubsub.publisher` the config
is created successfully and delivers nothing. Terraform grants it here.

**The notification is a POINTER, not the data.** Abstract needs `pubsub.subscriber` on the
subscription *and* `storage.objectViewer` on the bucket. Missing the second gives you
notifications with no content — which reads like a parser bug and is not one. Both are
granted here.

### Test end to end

```bash
gsutil cp /tmp/real-sample.gz gs://YOUR_BUCKET/logs/
```

Use a **real** file from the producer. A hand-made one is always the well-formed case,
which is exactly why it proves nothing.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then, with the same `backend.tf`:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
terraform destroy
```
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
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
