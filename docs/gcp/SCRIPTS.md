# The scripts

Two, with different jobs. **Run `preflight.sh` first, every time.**

| Script | Writes anything? | Job |
|---|---|---|
| `tools/gcp-guided-setup/preflight.sh` | **No — read-only** | Tell you what is already true before you build |
| `tools/gcp-guided-setup/deploy-abstract-gcp.sh` | Only with `--confirm` | Deploy without Terraform |

---

# preflight.sh

Terraform fails at **apply** when a permission is missing — after it has already created
some resources, leaving you with half a pipeline and a confusing error. This checks first.

Every command it runs is a `get` or a `list`. It changes nothing, and it is safe to run
against production during a customer call.

```bash
./tools/gcp-guided-setup/preflight.sh --project acme-security-logging --org-id 123456789012
```

## Options

| Flag | Meaning |
|---|---|
| `--project <id>` | **Required.** The logging project holding the topic and subscription |
| `--org-id <id>` | Organization ID. Without it the org-scope checks are skipped |
| `--folder-id <id>` | Folder ID. Implies `--scope folder` |
| `--scope <organization\|folder\|project>` | Which scope to check. Default `organization` |

Exit code is **1** if there is a blocker, **0** otherwise — so it works as a CI gate.

## What each section tells you

### Identity
Who `gcloud` is authenticated as. Everything below is evaluated for *that* principal, so a
surprise here explains every other result.

### APIs
Whether `pubsub.googleapis.com` and `logging.googleapis.com` are on. A warning, not a
blocker — `gcp-foundation-logging-project` turns them on.

### Permission at scope
**The check that matters.** It reads the IAM policy at the chosen scope and looks for
`roles/logging.configWriter`, `roles/logging.admin` or `roles/owner` bound to you.

If it comes back red:

```
✗ you do NOT hold roles/logging.configWriter at the ORGANIZATION.
```

**Stop.** This is the blocking prerequisite for an aggregated sink, and it is rarely held
by whoever owns the project. It is the single most common reason a GCP onboarding produces
a decision list instead of a working feed. Find the person who holds it before going any
further.

### Data Access audit logging
Two states, and the difference matters:

```
!  Data Access is NOT enabled anywhere at this scope.
   A sink filter referencing data_access will match NOTHING, with no error.
```

```
v  allServices: ADMIN_READ, DATA_WRITE
v  bigquery.googleapis.com: DATA_READ  (exempt: 1)
```

The first state is the trap this whole section exists for: filter for `data_access`
before enabling it and you get **zero events with no error**, which is indistinguishable
from a broken sink. Deploy `gcp-foundation-data-access-audit-logs` to fix it.

It also reminds you that **Admin Activity is always on and cannot be disabled** — there is
nothing to check and nothing to enable.

### Existing sinks
Lists org-level sinks that already exist. A warning here usually means these logs are
already being exported somewhere — worth knowing before you add a second export and pay
for both.

## Testing it without a GCP account

Every call goes through `gcloud`, so a stub on `PATH` exercises the whole script:

```bash
mkdir -p /tmp/stub && cat > /tmp/stub/gcloud <<'EOF'
#!/bin/sh
case "$*" in
  *"config get-value account"*) echo "tester@example.com" ;;
  *"json(auditConfigs)"*) echo '{}' ;;
  *) exit 0 ;;
esac
EOF
chmod +x /tmp/stub/gcloud
PATH=/tmp/stub:$PATH ./tools/gcp-guided-setup/preflight.sh --project p --org-id 1
```

That is how the blocker path and both Data Access states were verified.

---

# deploy-abstract-gcp.sh

For a customer with **no IaC practice at all**. It runs the same nine `gcloud` commands the
Terraform module encodes, printing each one before it runs.

**Dry-run by default.** Without `--confirm` it prints what it would do and changes nothing.

```bash
# Safe. Shows every command and the assembled filter.
./tools/gcp-guided-setup/deploy-abstract-gcp.sh \
  --scope organization --scope-id 123456789012 \
  --log-project acme-security-logging

# Same command, actually creates things.
./tools/gcp-guided-setup/deploy-abstract-gcp.sh \
  --scope organization --scope-id 123456789012 \
  --log-project acme-security-logging --confirm
```

## Options

| Flag | Meaning |
|---|---|
| `--scope <organization\|folder>` | **Required.** Only these two cover projects created later — the script refuses `project` |
| `--scope-id <id>` | **Required.** Organization or folder ID |
| `--log-project <id>` | **Required.** Dedicated logging project. Not a workload project |
| `--data-access` | Include Data Access audit logs. **Off by default** |
| `--data-access-services a,b` | Restrict Data Access. Default: BigQuery + Cloud Storage |
| `--platform-logs a,b` | Extra platform log IDs, e.g. `compute.googleapis.com%2Ffirewall` |
| `--retention-days N` | Pub/Sub retention, 1–31. Default 7 — **this is your entire recovery window** |
| `--topic` / `--subscription` / `--sink` / `--service-account` | Override generated names |
| `--rotate-key` | Mint a new service-account key even if one exists. GCP caps user-managed keys at 10 per account, and nothing here deletes old ones |
| `--confirm` | Actually create things |

## When to prefer Terraform instead

The script is a one-shot. It cannot tell you what **changed**, cannot reconcile drift, and
cannot remove what it created. If the customer has any IaC practice at all, use
`templates/gcp/gcp-source-audit-logs-organization` — you get a plan, a state file, and a way to change the
filter later without guessing what is currently deployed.

Use the script when the alternative is a human pasting commands from a PDF.

---

# Verifying a deployment — two behaviours that look like failure

**A sink is not live the instant Terraform returns.** Measured against a live org: events
written ~30 s and ~2 min after `CreateSink` were **never delivered**; an event at ~3 min
arrived in about a minute. Routing is write-time, so the early ones were never routed and
cannot be recovered. Wait five minutes, then fire a **fresh** event.

**A pull that does not acknowledge makes the next pull look empty.**
The first pull delivers the message but does not acknowledge it, so it stays inside the
60-second ack deadline and a second pull returns nothing. That reads as "it stopped
working". Use `--auto-ack` only on your own probe subscription, never on Abstract's.

```bash
PROBE=abstract-probe-$(date +%s)
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs \
  --project=P --expiration-period=1d
gcloud pubsub topics create abstract-probe-topic --project=P --quiet
gcloud pubsub topics delete abstract-probe-topic --project=P --quiet
sleep 75
gcloud pubsub subscriptions pull "$PROBE" --project=P --limit=5 --auto-ack
gcloud pubsub subscriptions delete "$PROBE" --project=P --quiet
```

Never pull from `abstract-audit-logs-sub`: Abstract reads that subscription, and `--auto-ack` there deletes events before Abstract sees them. The probe subscription above is yours and expires in a day.

---

# Which to use

```
Always:            preflight.sh
Guided, no install: the Cloud Shell button          → docs/DEPLOY-CLOUD-SHELL.md
Own CI and state:   terraform in templates/gcp/<template-id>/
Google holds state: Infrastructure Manager          → docs/DEPLOY-INFRA-MANAGER.md
No IaC practice:    deploy-abstract-gcp.sh
```
