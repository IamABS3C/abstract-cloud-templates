# The scripts

The guided setup is the one way to deploy without Terraform. Two read-only helpers sit beside it.
[The setup guide](GUIDE.md) says when each one runs.

| Script | Writes anything? | Job |
|---|---|---|
| `tools/gcp-guided-setup/abstract-gcp-setup.sh` | Only after you answer `y` | The guided setup: every step in order, a check mode, and a clean-up mode |
| `tools/gcp-guided-setup/audit-gcp-estate.sh` | **No, read-only** | List your organization, folders, projects, existing sinks and topics |
| `tools/gcp-guided-setup/preflight.sh` | **No, read-only** | Detail for one project: permissions at scope, APIs, Data Access state, existing sinks |

---

# preflight.sh

Terraform fails at **apply** when a permission is missing — after it has already created
some resources, leaving you with half a pipeline and a confusing error. This checks first.

Every call it makes only reads: a `get`, a `list`, or `testIamPermissions`, which asks Google
whether you hold a permission and changes nothing. It is safe to run against production during a
customer call.

```bash
./tools/gcp-guided-setup/preflight.sh --project acme-security-logging --org-id 123456789012
```

## Options

| Flag | Meaning |
|---|---|
| `--project <id>` | **Required.** The logging project holding the topic and subscription |
| `--org-id <id>` | Organization ID. Required at organization scope, the default: without it nothing at the organization is checked, and that is a blocker |
| `--folder-id <id>` | Folder ID. Implies `--scope folder`, and is required there |
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
**The check that matters.** It asks Google, with `testIamPermissions` at the chosen scope, whether
you can create sinks there: `logging.sinks.create`, which `roles/logging.configWriter` grants.
Google answers for every route to the permission, so a grant through a group, a custom role or a
parent folder counts.

If Google answers no, it is a blocker:

```
✗ you cannot create sinks at the organization (123456789012): logging.sinks.create (roles/logging.configWriter) is not held.
```

If you can change the IAM policy at that scope, it also prints the command that grants you the
role. If Google's answer cannot be read (no sign-in, a network error, or an error reply), it says
"could not check" as a warning, never a blocker, and names who to ask.

**Stop at a blocker.** This is the blocking prerequisite for an aggregated sink, and it is rarely held
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
v  bigquery.googleapis.com: DATA_READ
     exempted: serviceAccount:etl@acme-data.iam.gserviceaccount.com
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

A stub `gcloud` on `PATH` exercises the script without a Google Cloud account:

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

With `--org-id 1` it shows the Data Access "NOT enabled" state, and "could not check" for the
permission: that check asks Google directly, and the stub gives it no access token. It ends
"Ready to deploy" with exit code 0, because a check that could not run never blocks. Without
`--org-id` it shows the blocker path: "no --org-id given", and exit code 1.

---

# abstract-gcp-setup.sh

Walks through every piece in order and checks each one. Nothing changes without a `y`, every
command is printed before it runs, and your answers are kept in `~/.abstract-gcp-setup.env`, so
you can stop and resume.

| Command | What it does |
|---|---|
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh` | Every step, asking before each change |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4` | One step |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --check` | Checks everything and changes nothing |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove` | Lists what the clean-up would delete, and deletes nothing |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove --confirm` | Deletes that list. Run it only after you have read the list |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --remove --project <logging-project-id>` | With no answers file: lists by name what carries the setup's names, and deletes nothing |

`--state` names the answers file. In a new Cloud Shell session, upload the copy you downloaded
(More, then Upload), and if it is saved under another name, put that path after `--state`.

A Cloud Shell session opened from the templates button is temporary, so download the answers
file (`cloudshell download ~/.abstract-gcp-setup.env`) when the setup finishes. The clean-up
needs it to know what the setup made.

| Step | What it does |
|---|---|
| 1 | Sign-in, organization and scope (organization, folder or project) |
| 2 | Checks, live, every role the later steps need |
| 3 | Creates or picks the logging project, links billing, turns on the APIs |
| 4 | Topic, subscription, sink, and the sink's permission to publish |
| 5 | The service account Abstract reads with, and its key |
| 6 | Data Access audit logs (optional): both switches |
| 7 | Google Workspace reader (optional) |
| 8 | Health alerts (optional) |
| 9 | A fresh test event from the sink to the topic, on a probe subscription of its own |
| 10 | The exact values to enter in Abstract |

**Clean-up removes only what the setup created.** It records each thing it creates, so
`--remove` deletes the sink, topic, subscription, service accounts, alerts and key files it
made, and lists anything that existed before for you to decide on. Without the answers file it
lists what carries the setup's names and deletes nothing. It never deletes the logging
project. Without `--confirm` it only prints the list.

## When to use Terraform instead

If your team keeps infrastructure as code, use the Terraform appendix in each template's
tutorial. It creates a state bucket first, then runs `init`, `plan`, `apply`, and `destroy` to
clean up. It creates the same resources. Use one or the other for a given setup, not both.

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
END=$(( $(date +%s) + 330 )); FOUND=
for i in $(seq 1 20); do
  sleep 15
  while [ -z "$FOUND" ] && [ "$(date +%s)" -lt "$END" ]; do
    N=$(gcloud pubsub subscriptions pull "$PROBE" --project=P --limit=1000 --auto-ack --format=json 2>/dev/null \
      | python3 -c 'import base64, json, sys; m = json.load(sys.stdin) or []; print("FOUND" if any(sys.argv[1].encode() in base64.b64decode(x.get("message", {}).get("data", "")) for x in m) else len(m))' abstract-probe-topic 2>/dev/null)
    case "$N" in FOUND) FOUND=1 ;; ""|0) break ;; esac
  done
  [ -n "$FOUND" ] && { echo "FOUND: the sink routes and the topic delivers"; break; }
done
gcloud pubsub subscriptions delete "$PROBE" --project=P --quiet
```

Never pull from `abstract-audit-logs-sub`: Abstract reads that subscription, and `--auto-ack` there deletes events before Abstract sees them. The probe subscription above is yours and expires in a day.

---

# Which to use

```
Always first:        audit-gcp-estate.sh, then abstract-gcp-setup.sh --step 1 and --step 2
Deploy:              abstract-gcp-setup.sh (or the Terraform appendix, if you keep IaC)
Detail on a project: preflight.sh
Later, any time:     abstract-gcp-setup.sh --check
To remove it:        abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove, read the list, then add --confirm
```
