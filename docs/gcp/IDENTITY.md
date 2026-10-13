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

Admin Activity needs nothing. Impersonation and federation events need two switches (unlike
BigQuery, these services write no Data Access logs by default), and either alone does nothing,
with no error:

- **Switch 1, generate them.** Turn on Data Access in the audit settings for `iam.googleapis.com`
  and `sts.googleapis.com`. Google turns token-minting logs on only through the IAM API, so listing
  `iamcredentials.googleapis.com` in the audit settings does nothing. `ADMIN_READ` records
  `GenerateAccessToken` (impersonation) and the STS `ExchangeToken` (federation). For the other
  token methods Google's page disagrees with itself: Google's table of methods by permission type
  lists `GenerateAccessToken` and `SignJwt` under `ADMIN_READ`, and `GenerateIdToken`, `SignBlob`
  and `SignJwt` under `DATA_READ`, while its per-method entries give `SignBlob`, `SignJwt` and
  `GenerateIdToken` one `ADMIN_READ` and one `DATA_READ` permission each. So add `DATA_READ` on
  `iam.googleapis.com` to be sure of `SignBlob` and `GenerateIdToken`, and measure the volume.
- **Switch 2, route them.** The sink filter must include Data Access entries whose service is
  `iamcredentials.googleapis.com` (the name token-minting events carry) and `sts.googleapis.com`.

### With the guided script

Script step 6 does both by default. Its suggested services are BigQuery, Cloud Storage, Cloud KMS,
`iam.googleapis.com` and `sts.googleapis.com`, with `ADMIN_READ,DATA_WRITE`. Keep the last two:

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 6
```

The script lists what is missing, saves a copy of your current audit settings, and changes only the
audit settings. If you only want identity events, answer the services prompt with
`iam.googleapis.com,sts.googleapis.com`.

It then reports `switch 1` (the audit settings) and `switch 2` (the sink filter), naming
`iamcredentials.googleapis.com` and `sts.googleapis.com`. To read both yourself (read-only; ORG_ID comes from the answers file, `source ~/.abstract-gcp-setup.env`):

```bash
gcloud logging sinks describe abstract-org-audit-sink --organization="$ORG_ID" --format="value(filter)" | grep -o "iamcredentials.googleapis.com\|sts.googleapis.com"
gcloud organizations get-iam-policy "$ORG_ID" --format="yaml(auditConfigs)"
```

Both service names must show in the filter, and the audit settings must list `iam.googleapis.com`
and `sts.googleapis.com` with `ADMIN_READ`. Use `--folder=FOLDER_ID` or `--project=PROJECT_ID` for those
scopes.

### With Terraform

Switch 1 is [gcp-foundation-data-access-audit-logs](../../templates/gcp/gcp-foundation-data-access-audit-logs/README.md).
Set `scope` to your organization, folder or project, with its ID:

```hcl
scope     = "organization"
org_id    = "123456789012"
log_types = ["ADMIN_READ", "DATA_WRITE"]
services  = ["iam.googleapis.com", "sts.googleapis.com"]
acknowledge_authoritative_overwrite = true
```

The audit settings this template writes replace what is already there for each service it names, and
it applies ONE log_types list and ONE exempted_members list to every service it names. Before you set
`acknowledge_authoritative_overwrite`, run `tools/gcp-guided-setup/preflight.sh`: it marks each service
whose settings today differ from what the template sets. If `iam.googleapis.com` or `sts.googleapis.com`
already has DATA_READ or exempted members, leave it out of `services` (or manage it only from a separate
root with its own backend prefix, after removing it from this root's services) rather than copying those
settings into the lists, which would apply them to every named service.

Switch 2 is the audit-log sink template (organization, folder or project). Add `identity_access` to
its `log_categories` and apply it. `identity_access` routes Data Access entries for
`iamcredentials`, `sts`, `login` and Identity-Aware Proxy, and nothing else. Adding services to
`data_access_services` alone does nothing without `data_access_all`, because the sink reads that
list only for the `data_access_all` category. See [Filters](FILTERS.md).

Do not edit the organization policy by hand to add audit settings. If you must, change one service
at a time and keep a copy of the policy you started from.

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
Access on for `iam.googleapis.com` (see above) and a sink whose filter routes
`iamcredentials.googleapis.com`. The test grants you `roles/iam.serviceAccountTokenCreator` on a throwaway service account. The script
removes it on exit, even if you interrupt it. If the shell dies before it can, run the cleanup
commands at the end by hand, because the grant stays until someone removes it. It checks every 30
seconds, for up to 5 minutes.

Replace LOGGING_PROJECT_ID with your logging project's ID.

```bash
export LOG_PROJECT=LOGGING_PROJECT_ID
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
END=$(( $(date +%s) + 330 )); FOUND=
for i in $(seq 1 10); do
  sleep 30
  while [ -z "$FOUND" ] && [ "$(date +%s)" -lt "$END" ]; do
    N=$(gcloud pubsub subscriptions pull "$PROBE" --project=$LOG_PROJECT --limit=1000 --auto-ack --format=json 2>/dev/null \
      | python3 -c '
import base64, json, sys
m = json.load(sys.stdin) or []
for x in m:
    d = base64.b64decode(x.get("message", {}).get("data", "")).decode("utf-8", "replace")
    if "GenerateAccessToken" in d and sys.argv[1] in d: print("FOUND"); sys.exit(0)
print(len(m))' "$TEST_SA" 2>/dev/null)
    case "$N" in FOUND) FOUND=1 ;; ""|0) break ;; esac
  done
  [ -n "$FOUND" ] && { echo "FOUND"; break; }
done
```

If the shell stops before the trap runs, remove the grant and the leftovers by hand, with YOUR_ACCOUNT_EMAIL the account you ran it as:

```bash
gcloud iam service-accounts remove-iam-policy-binding "probe-identity@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" --member="user:YOUR_ACCOUNT_EMAIL" --role="roles/iam.serviceAccountTokenCreator"
```

```bash
gcloud iam service-accounts delete "probe-identity@$LOG_PROJECT.iam.gserviceaccount.com" --project="$LOG_PROJECT" --quiet
```

List any probe subscription left behind (read-only); each one expires a day after it was made:

```bash
gcloud pubsub subscriptions list --project="$LOG_PROJECT" --filter="name:abstract-probe"
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
