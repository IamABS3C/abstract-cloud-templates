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

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Step 1 — Get a real sample object first

```bash
gsutil ls -l gs://YOUR_BUCKET/** | head
gsutil cp gs://YOUR_BUCKET/some/object.gz /tmp/ && file /tmp/object.gz
```

Do this **first**. Every failure on this path traces back to a format assumption —
compression and wrapper shapes have broken it before. *"It's JSON"* is not a sample.

## Step 2 — List existing notification configs

```bash
gsutil notification list gs://YOUR_BUCKET
```

Adding a config **adds** to what is there; it does not replace. But you still want to know
whether something else is already consuming this bucket.

## Step 3 — Plan, then apply

```bash
cat > terraform.tfvars <<EOF
buckets            = ["YOUR_BUCKET"]
bucket_project     = "PROJECT_OWNING_THE_BUCKET"
log_project        = "YOUR_LOG_PROJECT"
object_name_prefix = "logs/"
EOF
terraform init && terraform plan
```

Scope `object_name_prefix` — an unscoped config notifies on every object written, and you
pay to fetch each one.

## Step 4 — The two permissions people miss

```bash
terraform output gcs_service_agents
```

**The GCS service agent publishes, not you** — and there is one PER OWNING PROJECT, which is why this output is a map. Without `roles/pubsub.publisher` the config
is created successfully and delivers nothing. Terraform grants it here.

**The notification is a POINTER, not the data.** Abstract needs `pubsub.subscriber` on the
subscription *and* `storage.objectViewer` on the bucket. Missing the second gives you
notifications with no content — which reads like a parser bug and is not one. Both are
granted here.

## Step 5 — Test end to end

```bash
gsutil cp /tmp/real-sample.gz gs://YOUR_BUCKET/logs/
```

Use a **real** file from the producer. A hand-made one is always the well-formed case,
which is exactly why it proves nothing.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

If the bucket is CMEK-encrypted, set `cmek_crypto_key_id` — otherwise every fetch fails
with an error that blames Storage rather than KMS, and sends you down the wrong path.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
