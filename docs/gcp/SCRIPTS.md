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
| `--project PROJECT_ID` | **Required.** The logging project holding the topic and subscription |
| `--org-id ORG_ID` | Organization ID. Required at organization scope, the default: without it nothing at the organization is checked, and that is a blocker |
| `--folder-id FOLDER_ID` | Folder ID. Implies `--scope folder`, and is required there |
| `--scope organization`, `folder` or `project` | Which scope to check. Default `organization` |

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
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --remove --project LOGGING_PROJECT_ID` | With no answers file, LOGGING_PROJECT_ID being your logging project's ID: lists by name what carries the setup's names, and deletes nothing |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --teardown` | Full reset, to start from scratch: lists everything the setup and the templates make across the organization, and deletes nothing |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --teardown --confirm` | Deletes that list, after you type the organization ID. Run it only after you have read the list |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant EMAIL --check` | The roles the setup needs, what each is for, and which of them EMAIL holds directly. Changes nothing |
| `./tools/gcp-guided-setup/abstract-gcp-setup.sh --grant EMAIL` | Run by someone who can set IAM policy: grants those roles to EMAIL, one binding per role, asking first |

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

**The full reset finds what the setup makes, whatever was recorded.** `--teardown` looks across the
organization (bounded, and it says when it stopped looking): sinks named `abstract-…` or sending to a topic
named `abstract-audit-logs`, at the organization and in its folders and projects; in every project, its
`abstract-…` topics and every subscription on them, the reader service accounts named `abstract-…-reader`
(deleting one deletes its keys) and, where it found a topic, the "Abstract log pipeline" alerts and channels;
at the organization, the Security Command Center notification configs and Cloud Asset feeds that send to one of
those topics. Cloud Storage bucket notifications cannot be found without reading every bucket, so for each
topic it prints how to find and delete them by hand. With `--confirm` it deletes the sinks, notification
configs and feeds first, so nothing is sent to a topic about to go, then subscriptions, topics, service
accounts and alerts. A listing it cannot read is a failure, never "none found", and the answers file stays;
the one exception is a project with the Pub/Sub or IAM API off, which holds none of these.
It lists and keeps your Data Access audit settings unless you add `--include-audit-settings`: then it takes
off exactly the log types script step 6 recorded adding (only what Google confirmed), at the scope where it
added them, after saving a copy, with the policy's etag and `updateMask=auditConfigs`. A log type that was on
before stays. With no such record it changes nothing and prints how to do it by hand. The bindings `--grant`
recorded stay unless you add `--include-grants`. It never deletes a project or Terraform state: it prints `gcloud projects delete` for each
logging project, and the `terraform state rm` lines for each template folder that still has state (the
topic, subscription and sink carry `prevent_destroy`, so `terraform destroy` refuses them). Without a terminal,
`--confirm` also needs `--yes-i-mean-it`.

**`--grant` adds the setup's roles one at a time.** Each is `add-iam-policy-binding` for one role (never a
write of the whole policy, which would replace every other binding), with `--condition=None` except on a billing account. A role
the person already holds directly is skipped and not recorded; each one added is recorded in the answers file,
so `--teardown --include-grants` removes exactly those. Script step 10, `--remove` and a plain `--teardown`
list each recorded binding with the `remove-iam-policy-binding` command that takes it back: run those once the
pipeline works, because the roles are not needed after the setup. The roles are listed in
[PERMISSIONS.md](PERMISSIONS.md#grant-exactly-these-roles-with---grant).

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
working".

Script step 9 handles both. It waits until the sink is old enough to route, writes a harmless admin event
inside your scope (it creates and deletes a log-based metric), and waits for that event on a throwaway
subscription on the same topic, acknowledging only there, then deletes the throwaway subscription. From the top
folder of the repository:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 9
```

Never pull from `abstract-audit-logs-sub` yourself: Abstract reads that subscription, and an acknowledged pull there deletes events before Abstract sees them.

---

# Which to use

```
Always first:        audit-gcp-estate.sh, then abstract-gcp-setup.sh --step 1 and --step 2
Deploy:              abstract-gcp-setup.sh (or the Terraform appendix, if you keep IaC)
Detail on a project: preflight.sh
Later, any time:     abstract-gcp-setup.sh --check
To remove it:        abstract-gcp-setup.sh --state ~/.abstract-gcp-setup.env --remove, read the list, then add --confirm
From scratch:        abstract-gcp-setup.sh --teardown, read the list, then add --confirm
Missing roles:       abstract-gcp-setup.sh --grant EMAIL --check, then an admin runs it without --check
```
