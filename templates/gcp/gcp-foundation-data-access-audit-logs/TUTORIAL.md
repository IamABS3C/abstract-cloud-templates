<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Enable Data Access audit logs

<!-- guided-step -->
> **This is step 6 of the guided setup (Data Access logs).** The guided setup does it for you and checks it: from the repository root run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6`, or follow `tools/gcp-guided-setup/WALKTHROUGH.md`. This page is the Terraform way to do the same step.
<!-- /guided-step -->

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

**Admin Activity is always on and cannot be disabled.** There is nothing to enable and
nothing here can turn it off.

**Only Data Access is off by default** — and until it is on, a sink filter referencing
`data_access` matches **nothing**, with no error, which is indistinguishable from a broken
sink.

<walkthrough-info-message>This is deliberately **separate state** from the log-export
pipeline. A `terraform destroy` of a collector must never be able to strip an
organization's audit logging.</walkthrough-info-message>

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Step 1 — See what is already enabled

```bash
../../../tools/gcp-guided-setup/preflight.sh --project YOUR_PROJECT --org-id YOUR_ORG_ID
```

Look at the **Data Access audit logging** section.

## Step 2 — Decide the scope of DATA_READ

This is the cost decision for the whole engagement.

- `ADMIN_READ` + `DATA_WRITE` on `allServices` — safe, low volume, high signal
- `DATA_READ` **only** on BigQuery and the buckets holding regulated data

BigQuery `DATA_READ` on a BigQuery-heavy estate can move total volume by one to two orders
of magnitude — and it is also where the exfiltration signal lives. **Scope it, don't refuse
it.**

## Step 3 — Apply

```bash
cat > terraform.tfvars <<EOF
scope     = "organization"
org_id    = "YOUR_ORG_ID"
log_types = ["ADMIN_READ", "DATA_WRITE"]
EOF
terraform init && terraform plan
```

You need **Organization Admin** — `resourcemanager.organizations.setIamPolicy`.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

**Inheritance is one-way.** A project can add Data Access logging but cannot disable what
the organization enabled — so scope deliberately at the org rather than blanket-enabling.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
