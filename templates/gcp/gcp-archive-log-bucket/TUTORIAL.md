<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Cold archive in Cloud Storage

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

<!-- abstract:needs -->
**This page uses Terraform, because the guided script builds only the streaming pipeline, and the archive is a second sink with a bucket (and an optional retention lock) of its own, which the template creates.**

Needs: Terraform (Cloud Shell has it), a Cloud Storage bucket for its state (the Terraform section creates it), and the roles under [Check first](#check-first). [Deploy with Terraform](#deploy-with-terraform), at the end of this page, deploys it.
<!-- /abstract:needs -->

A **second** sink writing to Cloud Storage. A sink has exactly one destination, so this
cannot be an extra destination on the streaming sink.

<walkthrough-info-message>**Not the detection path.** GCS batches, so latency becomes
minutes to hours. Keep Pub/Sub for anything you alert on, and use this for evidence you keep in your own
bucket.</walkthrough-info-message>

**Abstract does not read the archive today.** Nothing in this bucket reaches Abstract: it is a copy you search and
hand over from Cloud Storage. Sending archived logs to Abstract later (a backfill, or replay) is not something this
template or Abstract's Google Cloud integration does today.

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

- `roles/storage.admin` on the logging project: Create the bucket.
- `roles/logging.configWriter` on the organization: Create the organization archive sink.
- `roles/serviceusage.serviceUsageAdmin` on the logging project: Turn on the APIs this template uses. Terraform reads which are on and turns on only those still off.

Someone who can set IAM policy there adds each as one binding; nothing else in the policy changes. Replace PRINCIPAL with the person who deploys: `user:` and their email, `group:` and a group's email, or `serviceAccount:` and a service account's email.

Add `roles/storage.admin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/storage.admin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/storage.admin" --condition=None
```

Add `roles/logging.configWriter` for PRINCIPAL on your organization (ORG_ID):

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" --member="PRINCIPAL" --role="roles/logging.configWriter" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud organizations remove-iam-policy-binding "$ORG_ID" --member="PRINCIPAL" --role="roles/logging.configWriter" --condition=None
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

## Take the filter from the streaming deployment

The archive should capture exactly what the streaming sink sends. Print the streaming sink's filter (read-only; ORG_ID
comes from the answers file loaded in Check first). It reads the sink itself, so it works whether you deployed the
pipeline with the guided setup or with Terraform:

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization="$ORG_ID" --format='value(filter)'
```

You should see `logName:` clauses for `cloudaudit.googleapis.com`. Use that **exact string** as the archive's filter
(Deploy with Terraform, step 2, says where). An archive that quietly captures less than the stream is worse than no
archive, because you will trust it during an investigation.

## Decide retention, location and cost, carefully

The bucket's owner decides these, before the apply:

- **Retention** (`archive_retention_days`, default 0, meaning none). A retention policy keeps each object for that
  many days: nobody can delete it sooner. On its own, anyone with `storage.buckets.update` can shorten or remove it.
- **Lock** (`archive_retention_locked`, default false). A locked retention policy is what makes this evidentiary
  rather than a copy. It is **permanent**: the period can never be shortened or removed for the life of the bucket,
  by anyone, including you, including by mistake, including if you put the wrong logs in. Set it deliberately or
  leave it off.
- **Location** (`archive_bucket_location`, default `US`). Where the logs are stored; check your data-residency
  obligations before you accept the default. An organization policy on resource locations refuses any location it
  does not allow.
- **Cost.** Cloud Storage bills every byte routed here for as long as it is kept: Standard storage first, then
  Nearline after `archive_nearline_after_days` (default 30). With no retention and no deletion, storage grows until
  you choose a lifecycle or retention policy. The volume is the streaming filter's volume.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

These read, and change nothing. ORG_ID comes from the answers file loaded in Check first; replace ARCHIVE_BUCKET with
the `archive_bucket_name` you chose.

The archive sink exists and writes to your bucket. You should see abstract-org-audit-sink-archive, the bucket, and the
same filter as the streaming sink:

```bash
gcloud logging sinks describe abstract-org-audit-sink-archive --organization="$ORG_ID" --format="value(name,destination,filter)"
```

The archive sink has its **own** writer identity, distinct from the streaming sink's, and it gets its own grant. You
should see its identity (serviceAccount:…@gcp-sa-logging.iam.gserviceaccount.com) under roles/storage.objectCreator:

```bash
gcloud storage buckets get-iam-policy gs://ARCHIVE_BUCKET
```

Files arrive in batches, minutes to hours after the logs are written. Within a few hours, you should see folders named
after the log names (cloudaudit.googleapis.com…); an empty answer after that means the grant above is where to look:

```bash
gcloud storage ls gs://ARCHIVE_BUCKET
```

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
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

- `org_id`: your organization ID (ORG_ID; `echo "$ORG_ID"` prints it)
- `log_project`: your logging project ID (LOG_PROJECT; `echo "$LOG_PROJECT"` prints it)
- `archive_bucket_name`: a new bucket name, unique across all of Cloud Storage (start it with your organization's name)

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

Set `filter` to the exact string the streaming sink's filter printed (Take the filter from the streaming deployment,
above). It holds double quotes, so write it as a heredoc, which keeps them as they are; replace STREAMING_FILTER with
the printed filter:

```hcl
filter = <<-EOT
STREAMING_FILTER
EOT
```

If the organization pipeline was deployed with Terraform and its state is in a bucket, set `remote_state_bucket` to
that bucket instead (`LOGGING_PROJECT_ID-abstract-tfstate` when you followed its tutorial), and the filter is read from
its state. Set `archive_retention_days`, `archive_retention_locked` and `archive_bucket_location` as decided above;
each is commented out at its default until you set it.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(ARCHIVE_BUCKET_NAME|LOGGING_PROJECT_ID|ORG_ID|STREAMING_FILTER)\b' terraform.tfvars
```

Download the providers and connect to the state bucket:

```bash
terraform init
```

Preview, and save the plan:

```bash
terraform plan -out=abstract.tfplan
```

Apply exactly that plan. It creates what the plan listed; **To remove it later**, below, says what `terraform destroy` cannot remove:

```bash
terraform apply abstract.tfplan
```
<!-- /abstract:tfapply -->

<!-- abstract:tfremove -->
**To remove it later**, run `terraform destroy` in this folder with the same `backend.tf`. It removes what writes to the bucket, so nothing more arrives, but it cannot remove the bucket while the bucket holds objects: `force_destroy` is false, so Google refuses and a retention policy (`archive_retention_days`) keeps each object until its own retention ends; a locked policy (`archive_retention_locked = true`) can never be shortened or removed, by anyone, for the life of the bucket. The bucket, and its storage bill, stays until every object has passed its retention and been deleted; then run `terraform destroy` again to remove it.

In this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-archive-log-bucket"
```

Keep the bucket's name in ARCHIVE_BUCKET while Terraform still has it (read-only):

```bash
export ARCHIVE_BUCKET="$(terraform output -raw archive_bucket)"
```

Destroy what this template built (Terraform lists it and asks first):

```bash
terraform destroy
```

Only once you no longer need the archive: delete every object in it, every older version included. This **permanently deletes the archived logs**; nothing brings them back. Google refuses to delete an object still under its retention period, so run it after the retention has passed; with no retention policy (the default), it deletes everything at once:

```bash
gcloud storage rm --recursive --all-versions "gs://$ARCHIVE_BUCKET/**"
```

Then remove the empty bucket:

```bash
terraform destroy
```
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks)
- [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview#destinations)
- [Bucket Lock](https://docs.cloud.google.com/storage/docs/bucket-lock)
- [logging_organization_sink](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_organization_sink)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
