<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Enable Data Access audit logs

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

**Admin Activity is always on and cannot be disabled.** There is nothing to enable and
nothing here can turn it off.

**Only Data Access is off by default** — and until it is on, a sink filter referencing
`data_access` matches **nothing**, with no error, which is indistinguishable from a broken
sink.

<walkthrough-info-message>This is deliberately **separate state** from the log-export
pipeline. A `terraform destroy` of a collector must never be able to strip an
organization's audit logging.</walkthrough-info-message>

## Before you start

You need **Organization Admin** — `resourcemanager.organizations.setIamPolicy`.

**Inheritance is one-way.** A project can add Data Access logging but cannot disable what
the organization enabled — so scope deliberately at the org rather than blanket-enabling.

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

## Record identity: token minting and federation

Service account impersonation and token minting (`GenerateAccessToken`, `SignBlob`, `SignJwt`) and
Workload Identity Federation token exchange are among the highest-signal identity events in Google Cloud,
and they are Data Access logs: off until you turn them on. Two names matter, and they differ:

| | Turn it on here (`services`) | The events carry (sink `data_access_services`) |
|---|---|---|
| Token minting | `iam.googleapis.com` | `iamcredentials.googleapis.com` |
| Federation | `sts.googleapis.com` | `sts.googleapis.com` |

- Google turns token-minting logs on **only** through `iam.googleapis.com` (or allServices). Listing
  `iamcredentials.googleapis.com` in this template does nothing.
- Both are `ADMIN_READ`, so the default log types already cover them. No `DATA_READ` is needed.
- The sink in gcp-source-audit-logs-organization must route them too: add `iamcredentials.googleapis.com`
  and `sts.googleapis.com` to its `data_access_services`, then apply it before this template.
- `iam.googleapis.com` also records routine IAM reads. Those stay in Cloud Logging; the sink forwards only
  the token events.

The guided setup's script step 6 does all of this by default and checks both names.

## Decide the scope of DATA_READ

This is the cost decision for the whole engagement.

- `ADMIN_READ` + `DATA_WRITE` on `allServices` — safe, low volume, high signal
- `DATA_READ` **only** on BigQuery and the buckets holding regulated data

BigQuery `DATA_READ` on a BigQuery-heavy estate can move total volume by one to two orders
of magnitude — and it is also where the exfiltration signal lives. **Scope it, don't refuse
it.**

Set `scope = "organization"` and `log_types` (for example `["ADMIN_READ", "DATA_WRITE"]`)
in terraform.tfvars.

<!-- abstract:deploy -->
## Deploy

Run script step 6 of the guided setup. It needs the log pipeline from script steps 3 to 5; run those first. Each step prints its commands, asks before it changes anything, and checks the result. Run it again at any time: it only adds what is missing.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

Your team requires infrastructure as code? Use [Terraform instead](#terraform-instead) at the end of this page. Use one or the other, not both.
<!-- /abstract:deploy -->

## Verify

Until Data Access is on, a sink filter referencing `data_access` matches **nothing**, with
no error.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, so it stops reading. The clean-up needs the answers file the guided setup saved; in a new Cloud Shell session, upload the copy you downloaded at the end of the setup. Then list what the clean-up would remove, and remove it:

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove
./tools/gcp-guided-setup/abstract-gcp-setup.sh --state <answers-file> --remove --confirm
```

It removes only what the guided setup recorded creating, and never the logging project. Lost the answers file? `--remove --project <logging-project-id>` lists everything that carries the setup's names, with the command to remove each, and deletes nothing itself. If you deployed with Terraform instead, run `terraform destroy` in this folder with the same `backend.tf`.

terraform destroy turns Data Access audit logging OFF for every service this template manages, including any setting that existed before you applied it, because the audit config is authoritative for those services. Admin Activity logs are always on and are not affected.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Terraform instead

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-foundation-data-access-audit-logs"
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
