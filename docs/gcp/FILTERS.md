# Filters — inclusion, exclusion, and what each one costs

The filter decides **both your coverage and your bill**. It is the highest-leverage thing
in this repo and the easiest to get quietly wrong.

> **Routing is evaluated at WRITE TIME. There is no backfill.**
>
> A filter that was too narrow leaves a **permanent** hole — the logs were never routed,
> they are not queued anywhere, and no later change recovers them. One that was too wide
> costs money you can stop spending at any time.
>
> The asymmetry is the whole strategy: **start broad, measure for 7 days, then tighten.**

---

## You pick categories, the module writes the filter

```hcl
log_categories = ["admin_activity", "system_event", "policy_denied", "firewall"]
```

A name not in the catalog **fails at plan** with the valid list printed. That is
deliberate: a hand-written Cloud Logging filter fails *silently* — a typo matches nothing,
raises nothing, and is indistinguishable from a broken sink.

---

## The catalog

### Audit and identity — always collect these

| Category | Filter | Tier | What you get |
|---|---|---|---|
| `admin_activity` | `logName:"cloudaudit.googleapis.com%2Factivity"` | low | Every IAM change and every resource create/update/delete. **The highest-value stream in GCP.** Always on, cannot be disabled, free to generate |
| `system_event` | `…%2Fsystem_event` | low | Google-initiated actions — live migration, automatic restarts |
| `policy_denied` | `…%2Fpolicy` | low | Access denied by a security policy. **VPC Service Controls violations land here**, including dry-run violations. Always on, but charged |
| `access_transparency` | `…%2Faccess_transparency` | low | **Google-employee access to your data**, with the justification. Tiny volume, named control in most security questionnaires. Needs an eligible support tier or Assured Workloads — without it the stream does not exist and this collects nothing |
| `binary_authorization` | `binaryauthorization.googleapis.com%2Fcontinuous_validation` | low | Unsigned or unattested images admitted or blocked. **Distinct from** the policy-change events already in `admin_activity` — this is enforcement, those are configuration |

### Kubernetes

| Category | Filter | Tier | Notes |
|---|---|---|---|
| `gke_control_plane` | `(…%2Factivity AND protoPayload.serviceName=("k8s.io" OR "container.googleapis.com"))` | medium | Pod exec, RBAC changes, privileged workloads. The parser lifts pod exec into `process.command_line` — the container-breakout precursor. **Constrained to `activity` deliberately**, so it cannot silently start routing Data Access |
| `gke_container_logs` | `resource.type="k8s_container"` | **extreme** | Application stdout/stderr from every pod. Platform observability, rarely SOC |

### Networking

| Category | Filter | Tier | You must enable it where? |
|---|---|---|---|
| `firewall` | `logName:"compute.googleapis.com%2Ffirewall"` | medium | **Per firewall rule.** The sink cannot turn it on |
| `dns_queries` | `logName:"dns.googleapis.com%2Fdns_queries"` | high | **Per VPC network policy.** Off by default. The best C2 and exfil signal in GCP |
| `nat_flows` | `logName:"compute.googleapis.com%2Fnat_flows"` | high | Per NAT gateway. Egress attribution |
| `load_balancer` | `resource.type="http_load_balancer"` | high | **Per backend service** (`log_config { enable = true }`). Cloud Armor WAF decisions ride here. Note this matches the global HTTP(S) LB only |
| `vpc_flows` | `logName:"compute.googleapis.com%2Fvpc_flows"` | **extreme** | **Per subnet, with a sampling rate.** Sampling is the cost control and it belongs at the subnet, not in this filter |

> Four of these five need enabling somewhere else first. **The sink can only route what is
> already being generated** — adding the category and seeing nothing is the expected result
> if the source is off, and it looks exactly like a broken pipeline.

### Compute and databases

| Category | Tier | Notes |
|---|---|---|
| `cloud_run` | high | Cloud Run and Cloud Functions request logs plus stdout/stderr |
| `vm_guest` | high | Serial-port output. **Narrowed deliberately** — a bare `resource.type="gce_instance"` also matches every entry *attributed* to a VM org-wide, which is extreme volume wearing a high-tier label. For guest OS logs use a forwarder |
| `cloudsql` | high | Engine logs. Auth and admin are already in `admin_activity`; these add query-level detail |

### Data plane

| Category | Tier | Notes |
|---|---|---|
| `data_access_all` | **extreme** | Prefer `data_access_services` to scope it. Requires enabling in the IAM audit config first — see below |

---

## Data Access — the cost decision for the whole engagement

**Admin Activity is always on and cannot be disabled. Only Data Access is off by default.**

```hcl
log_categories       = [..., "data_access_all"]
data_access_services = [
  "bigquery.googleapis.com",   # query text, job detail, bytes billed — the exfil signal
  "storage.googleapis.com",    # object reads/writes with the object path
  "cloudkms.googleapis.com",   # key use — ransomware and exfil precursor, low volume
]
```

Leaving `data_access_services` empty means **allServices**, which on a BigQuery-heavy
estate moves total volume by **one to two orders of magnitude**. The module refuses it
without `acknowledge_high_volume`.

> **Scope it. Do not refuse it.** BigQuery `DATA_READ` is simultaneously the biggest cost
> driver *and* where the exfiltration signal lives. Refusing it outright trades the whole
> signal for the whole cost; scoping trades most of the cost for almost none of the signal.

**Three log types, and they are not equal:**

| Type | Volume | Recommendation |
|---|---|---|
| `ADMIN_READ` | Low | Enable everywhere. Metadata and config reads, high signal |
| `DATA_WRITE` | Moderate | Enable everywhere |
| `DATA_READ` | **Very high** | Named services only |

Enable them with `templates/gcp/gcp-foundation-data-access-audit-logs`. Until you do, a filter referencing
`data_access` matches **nothing, with no error**.

---

## Exclusions — filtering at the sink is free

```hcl
exclusions = [
  {
    name        = "exclude-health-checks"
    description = "GCP health-check probers. High volume, zero security signal."
    filter      = "protoPayload.requestMetadata.callerSuppliedUserAgent=~\"GoogleHC\""
  },
  {
    name        = "exclude-noisy-etl"
    description = "Known ETL service account. Dominates DATA_READ, carries no signal."
    filter      = "protoPayload.authenticationInfo.principalEmail=\"etl@acme.iam.gserviceaccount.com\""
  },
]
```

**Filters cost nothing to evaluate. Ingestion and Pub/Sub throughput are billed.** So every
byte you exclude at the sink is a byte you never pay to move, store or parse.

### Exclusions worth considering

| Exclude | Filter fragment | Why |
|---|---|---|
| Health-check probers | `callerSuppliedUserAgent=~"GoogleHC"` | Constant, zero signal |
| A named noisy service account | `principalEmail="etl@…"` | Often the single biggest `DATA_READ` contributor |
| GKE system namespaces | `resource.labels.namespace_name=("kube-system" OR "gke-system")` | Only if you took `gke_container_logs` |
| Successful reads on one dataset | `protoPayload.serviceName="bigquery.googleapis.com" AND protoPayload.authorizationInfo.granted=true AND …` | Surgical; keep denials |

### Two limits that shape this

- **50 exclusion filters per sink.** They are precious — prefer narrowing the *inclusion*
  filter over accumulating exclusions.
- **Filters cap at 20,000 characters.** A filter enumerating many services can hit this.
  Prefer `allServices` plus exclusions over a very long explicit list.

### The exclusion nobody thinks of

**Routing to Pub/Sub does not stop Cloud Logging bucket ingestion charges.** If logs are
being exported and *not* read in the console, you are paying twice. An exclusion on the
`_Default` bucket is the fix — and it is **not retroactive**, so decide early.

---

## Escape hatches

```hcl
# Add raw logName clauses the catalog does not cover
platform_log_filters = ["cloudaudit.googleapis.com%2Faccess_transparency"]

# Or replace the whole thing
custom_filter = "logName:\"cloudaudit.googleapis.com\" AND severity>=WARNING"
```

`custom_filter` overrides everything and bypasses every guard. Use it when you know
exactly what you want; you are on your own for volume.

---

## Read the filter before you apply

```bash
terraform plan
terraform output -raw effective_filter
```

Three outputs matter:

| Output | Use |
|---|---|
| `effective_filter` | The literal string. **Read it** |
| `selected_log_sources` | Each category with tier and rationale |
| `volume_profile` | Count by tier — any `extreme` needs a measured baseline |

### Test a filter against real data before committing to it

```bash
gcloud logging read 'PASTE_THE_FILTER' --limit=10 --freshness=1h --project=YOUR_PROJECT
```

And to estimate volume before routing anything:

```bash
gcloud logging read 'PASTE_THE_FILTER' --freshness=24h --format='value(logName)' \
  | sort | uniq -c | sort -rn | head -20
```

That breakdown by `logName` is the only honest input to a cost conversation. Everything
else is a guess.

---

## Changing the filter later

**Widening is safe.** It takes effect immediately and costs money you can stop spending.

**Narrowing is not.** From the moment it applies, the excluded logs are never routed and
cannot be recovered.

Before narrowing:

1. `terraform output -raw effective_filter > /tmp/before.txt`
2. Estimate the new filter's volume with `gcloud logging read` over 24 h
3. `terraform plan`, and diff the filter string
4. Confirm nobody is relying on what you are about to drop

Then apply. There is no undo.
