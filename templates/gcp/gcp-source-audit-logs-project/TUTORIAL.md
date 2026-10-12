<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Single-project pilot

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

<walkthrough-info-message>**This does not cover future projects.** A project sink has no
`include_children`, because nothing exists below a project. This is a pilot — it shows the
pipeline working, from the sink to events in Abstract, before you ask for organization-scope
IAM, which is usually the real blocker.</walkthrough-info-message>

Choosing this directory *is* the acknowledgement — the module normally refuses project
scope without one.

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in; `--update-adc` gives the scripts and Terraform the same sign-in:

```bash
gcloud auth login --update-adc
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

## Choose the project

In terraform.tfvars, set `sink_project` to the project whose logs you are piloting: the one running the
workload. Set `log_project` to the project that holds the topic and subscription; for a pilot it may be the
same project. `sink_project` has no default, so a pilot never exports an empty logging project by accident.

<!-- abstract:deploy -->
## Deploy

Run script steps 3, 4 and 5 of the guided setup: the logging project, then the pipeline, then the account Abstract reads with. Script step 9 then sends a test event and checks it reaches the topic from the sink, and script step 10 prints the values to enter in Abstract and the commands that download the key from this temporary session. Delete every copy of the key once Abstract has it. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 5
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 10
```

Your team requires infrastructure as code? Use [Terraform instead](#terraform-instead) at the end of this page. Use one or the other, not both.
<!-- /abstract:deploy -->

## Verify

Before you replace the pilot, confirm it delivers: script step 9 shows a test event reaching the topic from the sink, and Abstract shows the integration's events.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

## Then replace it

Once you have proven the pipeline and obtained `roles/logging.configWriter` at the
organization, deploy `gcp-source-audit-logs-organization` and **delete this sink**.

**Do not repeat this per project.** Seventy project sinks is exactly the linear toil the
aggregated sink exists to eliminate — and each one silently decays as projects change.

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, so it stops reading. The clean-up needs the answers file the guided setup saved, `~/.abstract-gcp-setup.env`; in a new Cloud Shell session, upload the copy you downloaded at the end of the setup to your home folder. First list what the clean-up would remove. This deletes nothing:

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove
```

When the list is right, remove it:

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm
```

It removes only what the guided setup recorded creating, and never the logging project. Lost the answers file? `--remove --project <logging-project-id>` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself. If you deployed with Terraform instead, follow **To remove it later** at the end of [Terraform instead](#terraform-instead).
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Terraform instead

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=<project-id-with-billing>` to put the bucket in a project that has it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-project"
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

**To remove it later**, delete the integration in Abstract first. The topic, the subscription and the sink carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the sink first so nothing is written to a topic that is about to go, then the subscription, then the topic. Use your own names if you changed them in terraform.tfvars:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-audit-logs-project"
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_project_sink.abstract[0]'
terraform destroy
gcloud logging sinks delete abstract-org-audit-sink --project=<sink-project-id>
gcloud pubsub subscriptions delete abstract-audit-logs-sub --project=<log-project-id>
gcloud pubsub topics delete abstract-audit-logs --project=<log-project-id>
```
<!-- /abstract:terraform -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)
- [Route logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/configure_export_v2#creating_sink)
- [Logging query language](https://docs.cloud.google.com/logging/docs/view/logging-query-language)
- [Subscription properties](https://docs.cloud.google.com/pubsub/docs/subscription-properties)
- [logging_project_sink](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/logging_project_sink)
- [pubsub_topic_iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/pubsub_topic_iam)
- [google_service_account_key](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_service_account_key)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
