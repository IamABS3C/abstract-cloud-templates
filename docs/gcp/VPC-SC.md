# VPC Service Controls

If the customer runs VPC Service Controls — common in regulated environments and near
universal in financial services — this deployment needs deliberate design, and the failure
mode if you skip it is an opaque `403`.

> **`unverified:` throughout.** Nothing in this document has been executed against a
> VPC-SC-protected organization. It is written from Google's published behaviour and the
> shape of this pipeline. **Confirm every rule with the customer's network security team
> before promising a VPC-SC-compatible deployment** — do not assume it works because the
> unprotected case does.

---

## Why it applies here

Both services this pipeline depends on are restrictable:

| Service | Role here |
|---|---|
| `logging.googleapis.com` | The sink, and the Log Router |
| `pubsub.googleapis.com` | The topic and subscription |
| `storage.googleapis.com` | The archive bucket, and the GCS-notifications path |
| `cloudasset.googleapis.com` | The asset-inventory feed |

And the consumer is outside the perimeter: **Abstract pulls from the subscription over the
public API surface.** That is an egress from the perimeter's point of view, and it is
denied by default.

---

## The three designs, in order of preference

### 1. Logging project outside the perimeter

Simplest and usually correct. The logging project holds no workload data — only telemetry
already destined for a third party — so putting it outside the perimeter changes little
about the risk while removing the whole problem.

**Confirm with the customer:** does the *content* of the audit logs itself fall inside the
data-protection boundary? For some regulators it does, and then this option is closed.

### 2. Ingress rule for Abstract's service account

Keep the logging project inside, and permit exactly one identity to pull.

```yaml
# Illustrative. Confirm with the customer's network security team.
- ingressFrom:
    identities:
      - serviceAccount:abstract-pubsub-reader@LOG_PROJECT.iam.gserviceaccount.com
    sources:
      - accessLevel: "*"
  ingressTo:
    operations:
      - serviceName: pubsub.googleapis.com
        methodSelectors:
          - method: "google.pubsub.v1.Subscriber.Pull"
          - method: "google.pubsub.v1.Subscriber.StreamingPull"
          - method: "google.pubsub.v1.Subscriber.Acknowledge"
    resources:
      - projects/LOG_PROJECT_NUMBER
```

**Notes that matter:**

- `StreamingPull` **and** `Pull` — a client may use either, and permitting only one
  produces an intermittent failure that looks like a network problem
- `Acknowledge` is required, and it is the one people forget. Without it messages are
  pulled, never acked, redelivered forever, and the subscription backlog grows while
  events *do* arrive in Abstract. Confusing, and it eventually expires the retention window
- `unverified:` whether Abstract's connector calls `GetSubscription` at startup. If it
  does, add `Subscriber.GetSubscription` — see the note in
  [PERMISSIONS.md](PERMISSIONS.md)

### 3. Private connectivity

Out of scope here. Abstract is a SaaS consumer; there is no private path today.

---

## The sink itself

An organization-scoped sink writing into a project **inside** a perimeter is a
cross-boundary write from the Log Router's service identity.

`unverified:` whether this requires an explicit ingress rule for the sink's writer
identity, or whether the Log Router is treated as a Google-managed service exempt from the
perimeter. **Test this in a non-production perimeter first** — and note the failure would
be silent from the sink's side, showing only as `exports/error_count`, which is exactly why
`gcp-monitoring-pipeline-health-alerts` alerts on it.

---

## Dry-run mode is the safe way to find out

VPC-SC supports a **dry-run** perimeter that logs what *would* be denied without denying
it.

```bash
gcloud access-context-manager perimeters dry-run describe PERIMETER --policy=POLICY_ID
```

Dry-run violations land in `cloudaudit.googleapis.com/policy` — which is
**`policy_denied`, in this repo's default `log_categories`.** So if the pipeline is already
running, the customer can see exactly what a perimeter would break *before* enforcing it.

That is the single most useful thing in this document: **deploy the pipeline first, put the
perimeter in dry-run, and read the denials.** It converts an architecture argument into a
list.

---

## Order of operations

1. Deploy the pipeline **before** enforcing the perimeter, if you have that choice
2. Put the perimeter in **dry-run** and let it run for a week
3. Read `policy_denied` for what would have been blocked
4. Write the ingress rules from the evidence rather than from a guess
5. Enforce
6. Watch `exports/error_count` and `oldest_unacked_message_age` — both alerted by
   `gcp-monitoring-pipeline-health-alerts` — for anything the dry run did not surface

## If you inherit an enforced perimeter

Expect a `403` with `VPC_SERVICE_CONTROLS` in the body. It is unambiguous once you know to
look for it, and it looks like a credentials problem until then.

```bash
gcloud logging read \
  'protoPayload.status.details.violations.type="VPC_SERVICE_CONTROLS"' \
  --limit=20 --project=LOG_PROJECT --freshness=1h
```

That query names the service, the method and the identity that was denied, which is the
whole diagnosis.
