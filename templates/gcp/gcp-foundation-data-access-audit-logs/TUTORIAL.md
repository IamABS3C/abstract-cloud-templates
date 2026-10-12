<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Enable Data Access audit logs

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

**Admin Activity is always on and cannot be disabled.** There is nothing to enable and
nothing here can turn it off.

**Data Access is off by default for every service except BigQuery**, which writes its Data Access
logs by default. For the others, until it is on, a sink filter referencing `data_access` matches
**nothing**, with no error, which is indistinguishable from a broken sink.

<walkthrough-info-message>This is deliberately **separate state** from the log-export
pipeline. A `terraform destroy` of a collector must never be able to strip an
organization's audit logging.</walkthrough-info-message>

## Before you start

You need the right to change the IAM policy at the scope you choose: `resourcemanager.organizations.setIamPolicy`,
`resourcemanager.folders.setIamPolicy` or `resourcemanager.projects.setIamPolicy`. Organization Administrator,
Folder Admin, Project IAM Admin and Security Admin each hold it at their level.

**Inheritance is one-way.** A project can add Data Access logging but cannot disable what
the organization enabled — so scope deliberately at the org rather than blanket-enabling.

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

## Record identity: token minting and federation

Service account impersonation and token minting (`GenerateAccessToken`, `SignBlob`, `SignJwt`) and
Workload Identity Federation token exchange are among the highest-signal identity events in Google Cloud,
and they are Data Access logs: off until you turn them on. Two names matter, and they differ:

| | Turn it on here (`services`) | The events carry (`serviceName`) |
|---|---|---|
| Token minting | `iam.googleapis.com` | `iamcredentials.googleapis.com` |
| Federation | `sts.googleapis.com` | `sts.googleapis.com` |

- Google turns token-minting logs on **only** through `iam.googleapis.com` (or allServices). Listing
  `iamcredentials.googleapis.com` in this template does nothing.
- `ADMIN_READ`, in the default log types, records `GenerateAccessToken` (impersonation) and the STS
  `ExchangeToken` (federation). For the other token methods Google's page disagrees with itself: Google's table
  of methods by permission type lists `GenerateAccessToken` and `SignJwt` under `ADMIN_READ`, and
  `GenerateIdToken`, `SignBlob` and `SignJwt` under `DATA_READ`, while its per-method entries give `SignBlob`,
  `SignJwt` and `GenerateIdToken` one `ADMIN_READ` and one `DATA_READ` permission each. So add `DATA_READ` on
  `iam.googleapis.com` to be sure of `SignBlob` and `GenerateIdToken`, and measure the volume. This
  template applies `log_types` to every service it names, so manage `iam.googleapis.com` only from a separate
  root with its own backend prefix, after removing it from this root's services. Let this root go of it without
  destroying its settings: remove `iam.googleapis.com` from `services`, run `terraform state rm` on its audit
  config (`terraform state list | grep iam.googleapis.com` prints the address), and check that the next plan here
  shows no destroy, because a destroy turns its Data Access logging off until the second root applies. Then copy
  this folder, set `services = ["iam.googleapis.com"]` and `log_types = ["ADMIN_READ", "DATA_WRITE", "DATA_READ"]`
  there, and give its `backend.tf` its own prefix (for example `audit-config-iam-read`), never this root's
  `05-audit-config`. Sharing this root's state would plan the destroy of every other service's audit config, and
  two roots naming the same service revert each other.
- The sink must route them too. In the sink you deployed (gcp-source-audit-logs-organization, -folder or
  -project), add `identity_access` to `log_categories` and apply that first. `identity_access` routes the
  `iamcredentials`, `sts`, `login` and `iap` entries; it is low volume and needs no acknowledgement.
- Adding the services to the sink's `data_access_services` alone does nothing: that list is read only when
  `data_access_all` is also in `log_categories`. The plan shows no change, and the events are never routed.
- BigQuery, Cloud Storage and KMS are not identity services: `identity_access` routes none of them. For those,
  also add `data_access_all` to the sink's `log_categories`; it routes the services in `data_access_services`,
  whose default already lists `bigquery.googleapis.com`, `storage.googleapis.com` and `cloudkms.googleapis.com`.
  If you changed that list, add the ones it lacks and keep the rest.
- `iam.googleapis.com` also records routine IAM reads. Those stay in Cloud Logging; the sink forwards only
  the token events.

The guided setup's script step 6 does all of this by default and checks both names.

## Decide the scope of DATA_READ

This is the cost decision for the whole engagement.

- `ADMIN_READ` + `DATA_WRITE` on **named services**: the guided setup's five, `bigquery.googleapis.com`,
  `storage.googleapis.com`, `cloudkms.googleapis.com`, `iam.googleapis.com` and `sts.googleapis.com`. Low
  volume, high signal.
- `DATA_READ` **only** on BigQuery and the buckets holding regulated data.

BigQuery `DATA_READ` on a BigQuery-heavy estate can move total volume by one to two orders
of magnitude — and it is also where the exfiltration signal lives. **Scope it, don't refuse
it.**

Avoid `allServices` (an empty `services` list). The audit config is **authoritative** for every service it
names: it replaces whatever log types and exempted members are already set on that service at this scope.
On `allServices` that means every service's settings, including ones a platform team or a landing zone put
there.

In terraform.tfvars, set `scope` (`organization`, `folder` or `project`) and the matching ID (`org_id`,
`folder_id` or `project_id`), then `log_types` and `services`:

```hcl
scope      = "organization"   # or "folder" / "project"
org_id     = "<org_id>"       # or folder_id / project_id
log_types  = ["ADMIN_READ", "DATA_WRITE"]
services   = ["bigquery.googleapis.com", "storage.googleapis.com", "cloudkms.googleapis.com", "iam.googleapis.com", "sts.googleapis.com"]
acknowledge_authoritative_overwrite = true
```

`acknowledge_authoritative_overwrite = true` is required on every apply. The template applies ONE log_types list and ONE exempted_members list to every service it names, and the apply replaces what each named
service has today with those two lists; `terraform destroy` removes them. So read what is enabled today first
(`tools/gcp-guided-setup/preflight.sh`, the "Data Access audit logging" section, which marks each service that
differs from what the template sets), and name only services whose existing settings you accept being
replaced. Leave out of `services` any service that already has DATA_READ or exempted members, or manage it only from a separate root with its own backend prefix, after removing it from this root's services. Copying one service's `DATA_READ` into `log_types`, or its exemptions into
`exempted_members`, applies them to every named service: `DATA_READ` everywhere is the cost driver, and an
exempted principal on `iam.googleapis.com` stops its token minting being recorded. To stop managing these
settings and leave logging as it is, run `terraform state rm 'module.audit_config'` instead of destroy.

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

To stop managing these settings and leave logging as it is, run terraform state rm 'module.audit_config' with the same backend.tf. terraform destroy instead turns Data Access audit logging OFF for every service this template manages, including any setting that existed before you applied it, because the audit config is authoritative for those services. Use it only to turn that logging off on purpose. Admin Activity logs are always on and are not affected.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Terraform instead

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=<project-id-with-billing>` to put the bucket in a project that has it.

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

**To remove it later**, decide what should happen to the logging it turned on. To stop managing it and leave Data Access logging exactly as it is (the usual offboarding), remove it from the state; nothing changes in Google Cloud:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-foundation-data-access-audit-logs"
terraform state rm 'module.audit_config'
```

Run `terraform destroy` only to turn this logging off on purpose: the audit config is authoritative, so destroy removes the Data Access settings for every service this template manages, including any that existed before you applied it.
<!-- /abstract:terraform -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up, and the Terraform provider's pages for the resources it creates:

- [Cloud Audit Logs overview](https://docs.cloud.google.com/logging/docs/audit#types)
- [Enable Data Access audit logs](https://docs.cloud.google.com/logging/docs/audit/configure-data-access#auditconfig_objects)
- [Identity and Access Management audit logging](https://docs.cloud.google.com/iam/docs/audit-logging)
- [Service Account Credentials audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-iamcreds)
- [Security Token Service audit logging](https://docs.cloud.google.com/iam/docs/audit-logging/audit-logging-sts)
- [google_organization_iam](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/google_organization_iam)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
