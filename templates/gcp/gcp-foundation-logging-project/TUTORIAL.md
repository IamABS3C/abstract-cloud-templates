<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Bootstrap the logging project

<!-- guided-step -->
> **This is step 3 of the guided setup (Logging project).** The guided setup does it for you and checks it: from the repository root run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 3`, or follow `tools/gcp-guided-setup/WALKTHROUGH.md`. This page is the Terraform way to do the same step.
<!-- /guided-step -->

<walkthrough-tutorial-duration duration="10"></walkthrough-tutorial-duration>

**Optional.** Most customers already have a security or logging project — point
`gcp-source-audit-logs-organization` at it and skip this.

Run this for greenfield, or when the only candidate is a **workload** project. That is the
wrong answer: Pub/Sub publish quota is consumed in the destination project, and a security
pipeline inside a workload project can be read or broken by that workload's owner.

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep the Terraform state outside this session.** Copy `backend.tf.example` to `backend.tf` and set its bucket before `terraform apply`, or the state is deleted when the session ends.</walkthrough-info-message>

## Enable APIs on an existing project

```bash
cat > terraform.tfvars <<EOF
project_id = "YOUR_EXISTING_PROJECT"
EOF
terraform init && terraform apply
```

## Or create the project too

```bash
cat > terraform.tfvars <<EOF
create_project     = true
project_id         = "acme-security-logging"
org_id             = "YOUR_ORG_ID"
billing_account_id = "XXXXXX-XXXXXX-XXXXXX"
EOF
```

Needs project-creator rights and a billing account — a project with no billing account
cannot publish to Pub/Sub.

`deletion_policy` defaults to **PREVENT**, which is right for a project holding an audit
pipeline.

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

```bash
terraform output preflight
```

That names the grants Terraform cannot verify for you — including
`roles/logging.configWriter` at the organization, the one that actually blocks people.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
