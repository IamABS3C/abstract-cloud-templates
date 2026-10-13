<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Logs already sitting in a bucket

<walkthrough-tutorial-duration duration="15"></walkthrough-tutorial-duration>

> [!WARNING]
> **Abstract keeps these files' contents only once a parser for their format is added to this subscription's own Abstract integration.** The managed GCP Pub/Sub parser keeps only Cloud Audit Log records. Ask Abstract for that parser first, with a real file from the product; until then this template costs a notification and a read per object in Google Cloud and adds nothing in Abstract.

<!-- abstract:needs -->
**This page uses Terraform, because the guided script builds only the audit-log pipeline, and watching a bucket needs a notification on each bucket and a grant in each project that owns one, which the template sets from your list.**

Needs: Terraform (Cloud Shell has it), a Cloud Storage bucket for its state (the Terraform section creates it), and the roles under [Check first](#check-first). [Deploy with Terraform](#deploy-with-terraform), at the end of this page, deploys it.
<!-- /abstract:needs -->

For vendor exports, third-party appliances, or an existing pipeline that already writes
objects into Cloud Storage.

```text
bucket → OBJECT_FINALIZE notification → Pub/Sub → Abstract fetches the object → the format parser keeps it
```

<walkthrough-info-message>**If the logs are Google's own, use `gcp-source-audit-logs-organization` instead.**
An aggregated sink is strictly better than watching buckets: one deployment, no
per-bucket wiring, and it covers resources created later.</walkthrough-info-message>

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in; `--update-adc` gives the scripts and Terraform the same sign-in:

```bash
gcloud auth login --update-adc
```
<!-- /abstract:signin -->

<!-- abstract:check -->
## Check first

Read-only, except the role grants at the end, which say what they add. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script step 1 of the guided setup records your organization and scope (ORG_ID, SCOPE_ID) in its answers file, `~/.abstract-gcp-setup.env`.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

List what you already have (read-only):

```bash
./tools/gcp-guided-setup/audit-gcp-estate.sh
```

Script step 1: your organization and scope.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
```

Load the answers into this terminal. It sets ORG_ID, and LOG_PROJECT if you ran the guided setup's script step 3 before:

```bash
source ~/.abstract-gcp-setup.env
```

This page also needs your logging project, the project that holds the topic and subscription. Check both are set. You should see your organization's number and your logging project's ID; "not set" names what to do:

```bash
echo "Organization: ${ORG_ID:?not set: run script step 1} Logging project: ${LOG_PROJECT:?not set: export LOG_PROJECT=LOGGING_PROJECT_ID}"
```

Only if it said the logging project is not set (you have not run script step 3): set it yourself, replacing LOGGING_PROJECT_ID with its ID, then run the check above again:

```bash
export LOG_PROJECT=LOGGING_PROJECT_ID
```

### The roles this page needs

The guided setup's own grant option covers only the roles its script steps need, not these. The person who deploys this template needs:

- `roles/pubsub.admin` on the logging project: Create the topic, subscription and IAM bindings.
- `roles/iam.serviceAccountAdmin` on the logging project: Create Abstract's service account, unless an existing one is passed.
- `roles/storage.admin` on each bucket: Add the notification and the reader grant to the bucket.
- `roles/serviceusage.serviceUsageAdmin` on the logging project: Turn on the APIs this template uses. Terraform reads which are on and turns on only those still off.
- `roles/cloudkms.admin` on the KMS key, CMEK buckets only: Only with cmek_crypto_key_id: grant Abstract's reader Decrypter on that key. Any role holding cloudkms.cryptoKeys.setIamPolicy on the key does; the key's owner decides.

Someone who can set IAM policy there adds each as one binding; nothing else in the policy changes. Replace PRINCIPAL with the person who deploys: `user:` and their email, `group:` and a group's email, or `serviceAccount:` and a service account's email.

Add `roles/pubsub.admin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

Add `roles/iam.serviceAccountAdmin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/iam.serviceAccountAdmin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/iam.serviceAccountAdmin" --condition=None
```

Add `roles/storage.admin` for PRINCIPAL on each bucket (replace YOUR_BUCKET with its name, and run it once per bucket):

```bash
gcloud storage buckets add-iam-policy-binding gs://YOUR_BUCKET --member="PRINCIPAL" --role="roles/storage.admin"
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud storage buckets remove-iam-policy-binding gs://YOUR_BUCKET --member="PRINCIPAL" --role="roles/storage.admin"
```

Add `roles/serviceusage.serviceUsageAdmin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
```

Removing this template later (**To remove it later**, at the end of the page) needs these roles again: add them back with the same commands first.
<!-- /abstract:check -->

## Get a real sample object first

Do this **first**: it is also the file to send Abstract when you ask for the parser. Every failure on this path traces
back to a format assumption — compression and wrapper shapes have broken it before. *"It's JSON"* is not a sample.
Replace YOUR_BUCKET with the bucket's name in each command below.

List a few of the bucket's objects, with sizes (read-only):

```bash
gcloud storage ls --long "gs://YOUR_BUCKET/**" | head
```

Copy one of them to a fixed name in this session. Replace OBJECT_PATH with a path the list showed, everything after
`gs://YOUR_BUCKET/`. It reads one object (one read, billed by Cloud Storage) and changes nothing in the bucket:

```bash
gcloud storage cp "gs://YOUR_BUCKET/OBJECT_PATH" /tmp/abstract-sample
```

Ask what kind of file it is. You should see a type such as `gzip compressed data`, `JSON data` or `ASCII text`:

```bash
file /tmp/abstract-sample
```

It is the file to send Abstract. In Cloud Shell, save it to your computer (this asks your browser to save one file):

```bash
cloudshell download /tmp/abstract-sample
```

Once Abstract has it, delete it here; it holds the producer's real logs:

```bash
rm -f /tmp/abstract-sample
```

## List existing notification configs

List the notifications the bucket already has (read-only):

```bash
gcloud storage buckets notifications list gs://YOUR_BUCKET
```

Adding a config **adds** to what is there; it does not replace. But you still want to know
whether something else is already consuming this bucket.

## Decide the prefix

The template notifies only on objects whose name starts with a prefix you choose, called OBJECT_PREFIX here: the
folder the producer writes into, such as the part of OBJECT_PATH before its file name, with its trailing `/`. Scope
it: an unscoped config notifies on every object written, and you pay to fetch each one. Deploy with Terraform, step 2,
says where it goes.

If the bucket is CMEK-encrypted, the template needs the key too — otherwise every fetch fails
with an error that blames Storage rather than KMS, and sends you down the wrong path.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

### The notification exists

These read, and change nothing. You should see one notification on the topic `abstract-gcs-notifications`, with
event type `OBJECT_FINALIZE` and your OBJECT_PREFIX:

```bash
gcloud storage buckets notifications list gs://YOUR_BUCKET
```

### The two permissions people miss

In this template's folder, print the Cloud Storage service agent of each project that owns a bucket. You should see
one `service-…@gs-project-accounts.iam.gserviceaccount.com` address per project:

```bash
terraform output gcs_service_agents
```

**The GCS service agent publishes, not you** — and there is one PER OWNING PROJECT, which is why this output is a map. Without `roles/pubsub.publisher` the config
is created successfully and delivers nothing. Terraform grants it here.

**The notification is a POINTER, not the data.** Abstract needs `pubsub.subscriber` on the
subscription *and* `storage.objectViewer` on the bucket. Missing the second gives you
notifications with no content — which reads like a parser bug and is not one. Both are
granted here.

### End to end

Leave the bucket alone: wait for the producer's next file under OBJECT_PREFIX. Once the integration is connected and
its format parser is on, that file's records appear in Abstract's event search, parsed. If they arrive unparsed, send
Abstract the sample you took above.

## Connect Abstract

Ask Abstract for the format parser first, with the sample file. Then [Deploy with Terraform](#deploy-with-terraform),
step 4, prints the values for Abstract's GCP Pub/Sub Source and makes the key; Abstract adds the parser to that
integration.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then follow **To remove it later** at the end of [Deploy with Terraform](#deploy-with-terraform), with the same `backend.tf`.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=PROJECT_ID_WITH_BILLING`, with your own project ID, to put the bucket in a project that has it.

Go to this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-cloud-storage-bucket-logs"
```

Load the guided setup's answers, if you ran it (it sets LOG_PROJECT and ORG_ID):

```bash
source ~/.abstract-gcp-setup.env
```

Check the logging project is set. If it says not set, run `export LOG_PROJECT=` and your logging project ID first:

```bash
echo "Logging project: ${LOG_PROJECT:?not set}"
```

Name the state bucket, in the logging project unless STATE_PROJECT is set:

```bash
export STATE_PROJECT="${STATE_PROJECT:-$LOG_PROJECT}" STATE_BUCKET="$LOG_PROJECT-abstract-tfstate"
```

Choose where the state bucket lives. Replace LOCATION with a Cloud Storage location your organization allows ([Bucket locations](https://docs.cloud.google.com/storage/docs/locations) lists them): the multi-region or region your data-residency rules name. An organization policy on resource locations refuses any other. A state bucket you created before stays where it is; this does not move it:

```bash
export STATE_LOCATION=LOCATION
```

Create the bucket, in STATE_PROJECT at STATE_LOCATION (to undo it once nothing uses the state, delete the bucket). If you made it before, Google answers that it already exists; go on:

```bash
gcloud storage buckets create "gs://$STATE_BUCKET" --project="$STATE_PROJECT" --location="$STATE_LOCATION" --uniform-bucket-level-access
```

Keep every version of the state:

```bash
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
```

Point `backend.tf` at the bucket:

```bash
sed "s/acme-abstract-tfstate/$STATE_BUCKET/" backend.tf.example > backend.tf
```

**2. Fill in your values.**

Copy the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Each value is described in the file. The required ones are not commented out, and hold an UPPERCASE placeholder until you replace it. Terraform does not notice one left behind, so **3. Preview** below checks for them before the plan.

Replace:

- `log_project`: your logging project ID (LOG_PROJECT; `echo "$LOG_PROJECT"` prints it)

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

Name the buckets and the prefix, with YOUR_BUCKET, BUCKET_PROJECT_ID (the project that owns the buckets) and
OBJECT_PREFIX as above:

```hcl
buckets            = ["YOUR_BUCKET"]
bucket_project     = "BUCKET_PROJECT_ID"
object_name_prefix = "OBJECT_PREFIX"
```

If the buckets span several projects, use `bucket_map` instead (each bucket mapped to its project; the file
describes it). If the bucket is CMEK-encrypted, set `cmek_crypto_key_id` to its key. That adds one grant outside
the pipeline: `roles/cloudkms.cryptoKeyDecrypter` for Abstract's reader account on that key, so the account can
decrypt anything the key protects that it can also read (other buckets on the same key included, where it has
read access). The key's owner decides; granting it needs a role with `cloudkms.cryptoKeys.setIamPolicy` on the key,
such as `roles/cloudkms.admin`. `terraform destroy` removes the grant, and so does removing `cmek_crypto_key_id`
and applying again.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(BUCKET_PROJECT_ID|LOGGING_PROJECT_ID|OBJECT_PREFIX|YOUR_BUCKET)\b' terraform.tfvars
```

Download the providers and connect to the state bucket:

```bash
terraform init
```

Preview, and save the plan:

```bash
terraform plan -out=abstract.tfplan
```

Apply exactly that plan. It creates what the plan listed; **To remove it later**, below, says how to take it away:

```bash
terraform apply abstract.tfplan
```

**4. Connect Abstract.** Terraform makes no key for Abstract, so no key sits in the state; make it with gcloud, once.

Print the values for Abstract (read-only):

```bash
terraform output abstract_onboarding
```

You should see `project_id`, your logging project: enter it as **Project ID** in Abstract's GCP Pub/Sub Source. `subscription_id` is the **Subscription ID**, the short name. `service_account_email` is the account the key below belongs to.

Keep the reader account's email in SA_EMAIL:

```bash
export SA_EMAIL="$(terraform output -json abstract_onboarding | jq -r .service_account_email)"
```

Check it. You should see an address ending in @ and your logging project's ID, then .iam.gserviceaccount.com:

```bash
echo "Reader account: ${SA_EMAIL:?not set: run the apply first}"
```

Make a folder for the key outside the repository clone, readable only by you:

```bash
mkdir -m 700 -p ~/abstract-keys
```

Create the key, as a file only you can read. This adds one key to the reader account in your logging project; anyone holding the file can read the subscription. The last command in this step revokes it:

```bash
(umask 077 && gcloud iam service-accounts keys create ~/abstract-keys/abstract-gcs-key.json --iam-account="$SA_EMAIL" --project="$LOG_PROJECT")
```

In Cloud Shell, save it to your computer:

```bash
cloudshell download ~/abstract-keys/abstract-gcs-key.json
```

Upload it to Abstract with the two values above. Once Abstract has saved the integration, delete the copy here, and the downloaded file on your computer:

```bash
rm -f ~/abstract-keys/abstract-gcs-key.json
```

To revoke the key later (a rotation, or removing the integration), list the reader account's keys (read-only). The one Abstract holds has the ID in the `private_key_id` of the file you uploaded:

```bash
gcloud iam service-accounts keys list --iam-account="$SA_EMAIL" --project="$LOG_PROJECT" --managed-by=user
```

Then delete it, replacing KEY_ID with that ID. Abstract can no longer read from that moment; nothing else changes:

```bash
gcloud iam service-accounts keys delete KEY_ID --iam-account="$SA_EMAIL" --project="$LOG_PROJECT"
```
<!-- /abstract:tfapply -->

<!-- abstract:tfremove -->
**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`.
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Pub/Sub notifications for Cloud Storage](https://docs.cloud.google.com/storage/docs/pubsub-notifications)
- [Create a topic](https://docs.cloud.google.com/pubsub/docs/create-topic)
- [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription)
- [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles)
- [pubsub_subscription](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
