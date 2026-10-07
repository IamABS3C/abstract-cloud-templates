<img src="../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Readiness assessment — start here

<!-- guided-step -->
> **This is step 2 of the guided setup (What you can change).** The guided setup does it for you and checks it: from the repository root run `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2`, or follow `tools/gcp-guided-setup/WALKTHROUGH.md`. This page is the Terraform way to do the same step.
<!-- /guided-step -->

<walkthrough-tutorial-duration duration="5"></walkthrough-tutorial-duration>

**Run this before anything else.** It is entirely read-only — every command is a `get` or
a `list` — so it is safe against production, safe on a customer call, and safe to run
before any decision has been made.

Terraform fails at **apply** when a permission is missing, *after* it has already created
some resources. This fails first, and tells you exactly what to fix.

<walkthrough-project-setup></walkthrough-project-setup>

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in:

```bash
gcloud auth login
```

## Step 1 — Set your context

```bash
export ORG_ID=$(gcloud organizations list --format='value(ID)' --limit=1)
export LOG_PROJECT=<walkthrough-project-id/>
echo "Organization: ${ORG_ID:-NONE FOUND}"
echo "Log project : $LOG_PROJECT"
```

If `ORG_ID` is empty you are not in an organization, and an aggregated sink is not
available to you. Stop here and talk to whoever owns the GCP hierarchy — that conversation
is the deployment.

## Step 2 — Run the assessment

```bash
./preflight.sh \
  --project "$LOG_PROJECT" \
  --org-id "$ORG_ID" \
  --report ~/abstract-readiness.md
```

## Step 3 — Read the result

It reports five things:

| Section | What it tells you |
|---|---|
| **Identity** | Who `gcloud` is authenticated as. Everything below is evaluated for *that* principal |
| **APIs** | Whether Pub/Sub and Logging are enabled on the logging project |
| **Permission at scope** | Whether you hold **`roles/logging.configWriter`** — the blocking prerequisite |
| **Data Access** | Whether it is on, and for which services |
| **Existing sinks** | Whether these logs are already being exported somewhere |

Then a numbered **Recommended next steps** list, and a verdict.

<walkthrough-info-message>**The check that matters is `roles/logging.configWriter` at the
ORGANIZATION.** It is rarely held by whoever owns the project, and it is the single most
common reason a GCP onboarding produces a decision list instead of a working feed. If that
line is red, finding the person who holds it *is* the next step.</walkthrough-info-message>

## Step 4 — Share the report

```bash
cat ~/abstract-readiness.md
```

A Markdown report you can paste into a ticket or send to whoever owns the org. It records
who ran it, at what scope, the pass/warn/blocker counts, the numbered actions, and the
facts that apply regardless of the result.

<walkthrough-info-message>**Two things it will tell you that are easy to get wrong.**
Admin Activity is **always on** and cannot be disabled — only Data Access needs enabling.
And routing is evaluated at **write time with no backfill**, so a filter that is too narrow
leaves a permanent hole.</walkthrough-info-message>

## Step 5 — Then deploy

```bash
cd ../../templates/gcp/gcp-source-audit-logs-organization
```

Exit code is **0** when ready and **1** when blocked, so this also works as a CI gate:

```bash
./preflight.sh --project "$P" --org-id "$O" || exit 1
```

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

Nothing was changed by any of the above. Every finding is something to fix *before* the
first `terraform apply`, which is exactly the point.

---

<sub>**Abstract Security · GCP log export** — [all scenarios](../../README.md) · [architecture](../../docs/gcp/ARCHITECTURE.md) · [permissions](../../docs/gcp/PERMISSIONS.md) · [filters](../../docs/gcp/FILTERS.md)</sub>
