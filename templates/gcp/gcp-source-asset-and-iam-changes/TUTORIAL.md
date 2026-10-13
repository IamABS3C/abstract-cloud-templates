<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Cloud Asset Inventory — resource and IAM-policy changes

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

> [!WARNING]
> **Abstract does not keep these logs today. Deploying this template costs money in Google Cloud and adds nothing in Abstract until Abstract's Google Cloud integration supports these records.** Abstract's Google Cloud integration keeps only Cloud Audit Logs, which asset and IAM-policy change records are not.

<!-- abstract:needs -->
**This page uses Terraform, because Cloud Asset Inventory publishes through an organization feed of its own, not a log sink, and the guided setup script builds only the sink.**

Needs: Terraform (Cloud Shell has it), a Cloud Storage bucket for its state (the Terraform section creates it), and the roles under [Check first](#check-first). [Deploy with Terraform](#deploy-with-terraform), at the end of this page, deploys it.
<!-- /abstract:needs -->

<walkthrough-info-message>**The third thing a log sink cannot carry.** Cloud Asset
Inventory publishes to Pub/Sub through its own feed. Not a sink, not a filter — no
widening of `log_categories` reaches it.</walkthrough-info-message>

Deploy this **alongside** `gcp-source-audit-logs-organization`, not instead of it. They answer different
questions:

| | Answers |
|---|---|
| `admin_activity` | **who called which API** |
| CAI `IAM_POLICY` | **what the policy now IS**, and what it was before |

Three different API paths to the same IAM binding produce three different audit entries and
**one identical policy diff**. The diff is what a detection actually wants — and it is also
the natural feed for an asset and identity model, because it carries inventory rather than
only events.

## Before you start

You need `roles/cloudasset.owner` at the organization.

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

- `roles/cloudasset.owner` on the organization: Create the organization feed.
- `roles/pubsub.admin` on the logging project: Create the topic, the subscription and their IAM bindings.
- `roles/serviceusage.serviceUsageAdmin` on the logging project: Turn on the APIs this template uses, and create the Cloud Asset Inventory service agent. Terraform turns on only the APIs still off.

Someone who can set IAM policy there adds each as one binding; nothing else in the policy changes. Replace PRINCIPAL with the person who deploys: `user:` and their email, `group:` and a group's email, or `serviceAccount:` and a service account's email.

Add `roles/cloudasset.owner` for PRINCIPAL on your organization (ORG_ID):

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" --member="PRINCIPAL" --role="roles/cloudasset.owner" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud organizations remove-iam-policy-binding "$ORG_ID" --member="PRINCIPAL" --role="roles/cloudasset.owner" --condition=None
```

Add `roles/pubsub.admin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
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

## Reuse Abstract's identity

The template grants the audit-log pipeline's reader account read access to this subscription, so no second
identity is needed once Abstract supports these records. Today Abstract does not read it, and that grant is one
more subscription the existing key can read; **To remove it later** takes it away. Deployed that pipeline with the guided setup? Its account is
`abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com`, with LOGGING_PROJECT_ID your logging project's
ID. Deployed it with Terraform? Its email is read from that template's state, or printed from its outputs, in Deploy
with Terraform, step 2.

## Choose the content type

`IAM_POLICY` is the default and the highest security value.

| Type | What it gives you |
|---|---|
| `IAM_POLICY` | Policy changes **with the prior state** |
| `RESOURCE` | Full resource metadata on change — inventory for an asset model |
| `ORG_POLICY` | Organization policy constraint changes |
| `ACCESS_POLICY` | **VPC Service Controls and Access Context Manager changes** |
| `OS_INVENTORY` | Installed packages and patches, where the Ops Agent runs |

## Scope the asset types

The default is a security-first set: projects, folders, service accounts, **service-account
keys**, buckets and firewalls.

<walkthrough-info-message>An **empty** `asset_types` feeds every asset type in the
organization. On a large estate that is a very large stream with a low signal ratio — the
module refuses it without `acknowledge_all_asset_types`.</walkthrough-info-message>

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

These read, and change nothing; ORG_ID and LOG_PROJECT come from the answers file loaded in Check first.

The feed exists on the organization. You should see `abstract-asset-feed`, publishing to the `abstract-asset-changes`
topic in your logging project:

```bash
gcloud asset feeds list --organization="$ORG_ID"
```

CAI publishes as its **own service agent**, not as you — the same shape as the Log Router
writer identity and the GCS service agent. Without `roles/pubsub.publisher` on the topic
the feed is created successfully and delivers nothing. Terraform grants it here. You should see
`service-…@gcp-sa-cloudasset.iam.gserviceaccount.com` under roles/pubsub.publisher:

```bash
gcloud pubsub topics get-iam-policy abstract-asset-changes --project="$LOG_PROJECT"
```

If that identity is missing, print the one this template expects, in its folder, and run `terraform apply` again:

```bash
terraform output cai_service_agent
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Asset changes arrive on their **own** topic and subscription. Abstract does not keep them today: its Google Cloud
integration keeps only Cloud Audit Logs. Remove the template (below) if you deployed it only for Abstract.

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
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
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

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

Name the account Abstract already reads with. Deployed the audit-log pipeline with the guided setup? Set
`subscriber_service_account_email` to `abstract-pubsub-reader@LOGGING_PROJECT_ID.iam.gserviceaccount.com`, with
LOGGING_PROJECT_ID your logging project's ID. Deployed `gcp-source-audit-logs-organization` with Terraform, its state
in the bucket its tutorial created? Read it from that state instead of retyping it:

```hcl
remote_state_bucket = "LOGGING_PROJECT_ID-abstract-tfstate"
remote_state_prefix = "01-organization"
```

`01-organization` is that template's state key: it keeps the original folder name, so existing state is found. With
Terraform state kept somewhere else, print the email from that template's outputs (read-only) and set it as
`subscriber_service_account_email`; you then own keeping it in sync:

```bash
terraform -chdir="$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-organization" output -json abstract_onboarding | jq -r .service_account_email
```

`-json | jq`, not `-raw`: **`-raw` errors on an object output.**

`content_type` defaults to `IAM_POLICY`, and `asset_types` to the security-first set above. An empty `asset_types`
feeds every asset type and needs `acknowledge_all_asset_types = true`.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(LOGGING_PROJECT_ID|ORG_ID)\b' terraform.tfvars
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
<!-- /abstract:tfapply -->

<!-- abstract:tfremove -->
**To remove it later**, delete the integration in Abstract first. The topic and the subscription carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the subscription first, then the topic. Use your own names if you changed them in terraform.tfvars.

The commands below use the guided setup's answers (LOG_PROJECT, ORG_ID, SCOPE_ID), saved in `~/.abstract-gcp-setup.env`. Load them in this terminal; without the guided setup, `export` each one instead:

```bash
source ~/.abstract-gcp-setup.env
```

In this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-asset-and-iam-changes"
```

Take them out of the state (this deletes nothing):

```bash
terraform state rm 'module.asset_inventory.google_pubsub_topic.assets' 'module.asset_inventory.google_pubsub_subscription.assets'
```

Destroy the rest of what this template built (Terraform lists it and asks first):

```bash
terraform destroy
```

Delete the subscription abstract-asset-changes-sub, and every event in it not yet read:

```bash
gcloud pubsub subscriptions delete abstract-asset-changes-sub --project="$LOG_PROJECT" --quiet
```

Delete the topic abstract-asset-changes:

```bash
gcloud pubsub topics delete abstract-asset-changes --project="$LOG_PROJECT" --quiet
```
<!-- /abstract:tfremove -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Monitor asset changes with Pub/Sub](https://docs.cloud.google.com/asset-inventory/docs/monitor-asset-changes#create_feeds)
- [Create pull subscriptions](https://docs.cloud.google.com/pubsub/docs/create-subscription#create_a_pull_subscription)
- [Access control with Identity and Access Management](https://docs.cloud.google.com/pubsub/docs/access-control#roles)
- [pubsub_subscription](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_subscription)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
