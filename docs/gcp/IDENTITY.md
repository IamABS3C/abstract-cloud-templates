# Identity logs

Which Google Cloud and Google Workspace sign-in and credential events Abstract can collect, where
each one lives, and what has to be switched on. Identity is where most investigations start, and
it is where the most common gaps are.

Ask what the customer means first. "Identity logs" can mean four different things, and each comes
from a different place.

---

## Where each identity event lives

| You want to see | Service in the log | Log stream | Collected with |
|---|---|---|---|
| Console and `gcloud` sign-ins, IAM changes, service account and key creation | Many, such as `iam.googleapis.com` | Admin Activity (`activity`) | Any audit-log sink. Always on |
| Service account impersonation and token minting | `iamcredentials.googleapis.com` | Data Access (`data_access`) | An audit-log sink with `identity_access`, after you turn Data Access on for that service |
| Workload Identity Federation token exchange | `sts.googleapis.com` | Data Access (`data_access`) | The same |
| Access denied by a security policy | Many | Policy denied (`policy`) | An audit-log sink with `policy_denied` |
| Workspace user sign-ins, MFA challenges, suspicious login flags | Workspace `login` application | Admin SDK Reports API | The Google Workspace integration. See [Google Workspace](WORKSPACE.md) |

Two of these are easy to miss. Service account impersonation and Workload Identity Federation
leave no trace in Admin Activity. They only appear in Data Access, which is off by default. An
organization that collects Admin Activity alone cannot see an attacker moving between service
accounts with `roles/iam.serviceAccountTokenCreator`.

Workspace sign-ins are collected through the Reports API, not a log sink. Google also offers an
option to share Workspace audit logs with Cloud Logging, and the `identity_access` filter would
match those entries if it is on. This repo has not verified that option end to end, so rely on the
Reports API path for Workspace.

---

## Turn on what is off

Admin Activity needs nothing. For impersonation and federation events, turn on Data Access for
those two services only.

With the guided script, run step 6, and do not accept its defaults. The defaults are BigQuery,
Cloud Storage and KMS with `ADMIN_READ,DATA_WRITE`, which log neither IAM Credentials nor STS:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

Answer the two prompts like this. Keep any services and log types you already have and add to
them:

| Prompt | Enter |
|---|---|
| `Services (comma-separated)` | `bigquery.googleapis.com,storage.googleapis.com,cloudkms.googleapis.com,iamcredentials.googleapis.com,sts.googleapis.com` (your existing list plus the last two) |
| `Log types (ADMIN_READ, DATA_WRITE, DATA_READ)` | `ADMIN_READ,DATA_WRITE,DATA_READ` |

The script lists what is missing, saves a copy of your current audit settings, and changes only the
audit settings. Log types apply to every service you list, so `DATA_READ` is switched on for
BigQuery, Storage and KMS too, which is the high-volume choice. If you only want identity events,
enter only `iamcredentials.googleapis.com,sts.googleapis.com`.

Then check both switches. The script reports `switch 1` (audit config) and `switch 2` (sink
filter). If the sink already routed some Data Access logs, switch 2 can pass without the new
services in the filter, so re-run step 4 and read the filter yourself:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 4
gcloud logging sinks describe abstract-org-audit-sink --organization=123456789012 \
  --format="value(filter)" | grep -o "iamcredentials.googleapis.com\|sts.googleapis.com"
gcloud organizations get-iam-policy 123456789012 --format="yaml(auditConfigs)"
```

Both service names must show in the filter, and the audit config must list both with `DATA_READ`.
Use `--folder=<id>` or `--project=<id>` for those scopes.

With Terraform, use [gcp-foundation-data-access-audit-logs](../../templates/gcp/gcp-foundation-data-access-audit-logs/README.md):

```hcl
scope     = "organization"
org_id    = "123456789012"
log_types = ["ADMIN_READ", "DATA_WRITE", "DATA_READ"]
services  = ["iamcredentials.googleapis.com", "sts.googleapis.com", "login.googleapis.com"]
```

Naming the services keeps volume small. Leaving the list empty means every service, which is the
expensive choice and needs an explicit acknowledgement.

There are two switches, and you need both. Turning Data Access on at the source makes Google write
the logs. The sink filter then has to include them. In the audit-log templates, add the
`identity_access` category to `log_categories`. It matches Data Access entries for
`iamcredentials`, `sts`, `login` and Identity-Aware Proxy, and nothing else. A filter that names
Data Access before it is on matches nothing and raises no error. See [Filters](FILTERS.md).

Audit settings are set per service and replace what is there for that service. Run
`tools/gcp-guided-setup/preflight.sh` first to see what is already enabled. Do not edit the
organization policy by hand to add them. If you must, change one binding at a time and keep a copy
of the policy you started from.

Cost: `iamcredentials` and `sts` are small next to BigQuery or Cloud Storage reads. Measure for seven
days before widening.

---

## What the events look like

Impersonation. The `serviceAccountDelegationInfo` list keeps each hop, in order, so a chain from a
user through two service accounts is visible:

```json
{
  "protoPayload": {
    "serviceName": "iamcredentials.googleapis.com",
    "methodName": "GenerateAccessToken",
    "resourceName": "projects/-/serviceAccounts/deployer@acme-prod.iam.gserviceaccount.com",
    "authenticationInfo": {
      "principalEmail": "user@example.com",
      "serviceAccountDelegationInfo": [
        { "firstPartyPrincipal": { "principalEmail": "user@example.com" } }
      ]
    },
    "requestMetadata": { "callerIp": "203.0.113.15" }
  }
}
```

The methods to know are `GenerateAccessToken`, `GenerateIdToken`, `SignBlob` and `SignJwt`.

Workload Identity Federation. A token exchange shows the pool, the provider and the federated
subject:

```json
{
  "protoPayload": {
    "serviceName": "sts.googleapis.com",
    "methodName": "google.identity.sts.v1.SecurityTokenService.ExchangeToken",
    "resourceName": "projects/1234567890/locations/global/workloadIdentityPools/ci-pool/providers/ci-provider",
    "authenticationInfo": {
      "principalSubject": "//iam.googleapis.com/projects/1234567890/locations/global/workloadIdentityPools/ci-pool/subject/repo:acme/service:ref:refs/heads/main"
    },
    "requestMetadata": { "callerIp": "198.51.100.10" }
  }
}
```

Static service account keys. When a call is made with a downloaded key,
`authenticationInfo.serviceAccountKeyName` holds the key's resource path. When it is made through
the metadata server, impersonation or federation, that field is absent. A key used from an address
you do not recognise is the strongest sign of a leaked key.

Workspace sign-ins arrive from the Reports API in a different shape. The methods you will see in
the `login` application include successful and failed logins, logouts and suspicious-login flags,
with the challenge method and its result for 2-step verification.

---

## What to alert on

These are starting points. Test each against your own data before relying on it.

| Signal | Where it shows | Why it matters |
|---|---|---|
| New service account key | `CreateServiceAccountKey` in Admin Activity | A key is a long-lived credential and a common backdoor |
| Key deleted | `DeleteServiceAccountKey` | Evidence removal |
| Owner, editor or token creator granted | `SetIamPolicy` in Admin Activity | Privilege escalation |
| Impersonation by a principal that never did it before | `GenerateAccessToken` in Data Access | Lateral movement |
| Federation from an unexpected repository or branch | `ExchangeToken` subject | Supply chain compromise |
| Key used from outside your address ranges | `serviceAccountKeyName` with `callerIp` | Leaked key |
| Repeated login failures, or repeated failed challenges | Workspace `login` application | Password guessing or MFA fatigue |
| A sink deleted or its filter changed | `DeleteSink`, `UpdateSink` in Admin Activity | Someone is blinding you. Alert on this at every scope |

Write the alert in Abstract against fields you have confirmed exist on your tenant. A field name
that does not exist matches nothing and does not warn you.

---

## Check that it works

Make an impersonation call on purpose and look for it on a probe subscription. This needs Data
Access on for `iamcredentials.googleapis.com` (see above) and a sink whose filter includes it. The
test grants you `roles/iam.serviceAccountTokenCreator` on a throwaway service account. The script
removes it on exit, even if you interrupt it. If the shell dies before it can, run the cleanup
commands at the end by hand, because the grant stays until someone removes it.

```bash
export LOG_PROJECT=acme-security-logging
TEST_SA=probe-identity@${LOG_PROJECT}.iam.gserviceaccount.com
ME=$(gcloud config get-value account)
PROBE=abstract-probe-$(date +%s)

cleanup() {
  gcloud pubsub subscriptions delete "$PROBE" --project=$LOG_PROJECT --quiet 2>/dev/null
  gcloud iam service-accounts remove-iam-policy-binding "$TEST_SA" --project=$LOG_PROJECT \
    --member="user:$ME" --role="roles/iam.serviceAccountTokenCreator" 2>/dev/null
  gcloud iam service-accounts delete "$TEST_SA" --project=$LOG_PROJECT --quiet 2>/dev/null
}
trap cleanup EXIT

gcloud iam service-accounts create probe-identity --project=$LOG_PROJECT
gcloud iam service-accounts add-iam-policy-binding "$TEST_SA" --project=$LOG_PROJECT \
  --member="user:$ME" --role="roles/iam.serviceAccountTokenCreator"
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-audit-logs \
  --project=$LOG_PROJECT --expiration-period=1d --message-retention-duration=10m

gcloud auth print-access-token --impersonate-service-account="$TEST_SA" >/dev/null
for i in $(seq 1 10); do   # every 30 s, up to 5 minutes
  sleep 30
  gcloud pubsub subscriptions pull "$PROBE" --project=$LOG_PROJECT --limit=50 --format=json 2>/dev/null \
    | python3 -c '
import base64, json, sys
for m in json.load(sys.stdin) or []:
    d = base64.b64decode(m.get("message", {}).get("data", "")).decode("utf-8", "replace")
    if "GenerateAccessToken" in d and sys.argv[1] in d: print("FOUND"); sys.exit(0)
sys.exit(1)' "$TEST_SA" && break
done
```

If the shell stops before the trap runs, remove the grant and the leftovers by hand:

```bash
gcloud iam service-accounts remove-iam-policy-binding probe-identity@acme-security-logging.iam.gserviceaccount.com \
  --project=acme-security-logging --member="user:<your-account>" --role="roles/iam.serviceAccountTokenCreator"
gcloud iam service-accounts delete probe-identity@acme-security-logging.iam.gserviceaccount.com \
  --project=acme-security-logging --quiet
gcloud pubsub subscriptions list --project=acme-security-logging --filter="name:abstract-probe"
```

`FOUND` means the identity path works: the message body names both the method and your test service account. Nothing found means the same as any quiet feed: it is a
claim to prove, not a result. Work through [Troubleshooting](TROUBLESHOOTING.md). The probe reads
a subscription of its own and never touches the one Abstract reads.

---

## Related

- [Google Workspace](WORKSPACE.md): the Reports API path for sign-ins
- [Filters](FILTERS.md): categories, Data Access scoping and cost
- [Permissions](PERMISSIONS.md): who needs which role
- [The data flow](DATAFLOW.md): how each path reaches Abstract
