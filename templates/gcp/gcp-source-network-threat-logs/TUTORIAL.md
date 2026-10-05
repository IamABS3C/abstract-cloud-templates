<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export Network Threat Telemetry to Abstract Security

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

Network threat detection is a primary security workload in Google Cloud. This tutorial walks you through deploying an aggregated export pipeline for all four network telemetry pillars:

1. **Cloud Armor WAF decisions**, inside Application Load Balancer request logs (`resource.type` `http_load_balancer`, `http_external_regional_lb_rule` and `internal_http_lb_rule`)
2. **Cloud IDS threat logs** (`logName:"ids.googleapis.com%2Fthreat"`)
3. **VPC DNS query logs** (`logName:"dns.googleapis.com%2Fdns_queries"`)
4. **Firewall rule decisions** (`logName:"compute.googleapis.com%2Ffirewall"`)

All four streams route into a single Pub/Sub topic and pull subscription in your dedicated security logging project.

> [!WARNING]
> **These logs reach the Pub/Sub topic; Abstract's managed GCP parser does not yet store them.** The managed GCP Pub/Sub parser keeps only Cloud Audit Log records, and firewall, DNS, Cloud Armor and Cloud IDS logs are not audit logs. There is no parser for them yet. Do not rely on them for detection until a parser ships.

## Sign in first

Cloud Shell opened this repository in a **temporary** session: Google gives repositories it does not own none of your credentials, and deletes the session's files when it ends.

Sign in, then give Terraform the same sign-in:

```bash
gcloud auth login
gcloud auth application-default login
```

<walkthrough-info-message>**Keep Terraform state outside this temporary session.** Copy `backend.tf.example` to `backend.tf` and configure a Cloud Storage bucket before `terraform apply`, or your state will be deleted when the Cloud Shell session terminates.</walkthrough-info-message>

```bash
cp backend.tf.example backend.tf
```

## Before you start

<walkthrough-project-setup></walkthrough-project-setup>

You need the following permissions:

1. **`roles/logging.configWriter` at ORGANIZATION or FOLDER scope**: Required to create the aggregated log sink across your estate.
2. **`roles/pubsub.admin`** on the logging project: To manage the Pub/Sub topic and subscription.
3. **`roles/iam.serviceAccountAdmin`** on the logging project: To create the Abstract subscriber identity.

Set your environment variables:

```bash
export LOG_PROJECT=<walkthrough-project-id/>
# Pick the organization explicitly: taking the first one listed can bind the sink to the wrong one.
gcloud organizations list --format='table(ID,displayName)'
export ORG_ID=""   # paste one ID from the list above
: "${ORG_ID:?set ORG_ID to one ID from the list above}"
echo "Logging Project: $LOG_PROJECT"
echo "Organization ID: $ORG_ID"
```

<walkthrough-info-message>Always use a **dedicated logging project** rather than a workload project. Workload owners should not possess access to read or modify security pipelines, and Pub/Sub quota is consumed in this project.</walkthrough-info-message>

## Step 1 — Verify Cloud Armor Logging

Cloud Armor security policy evaluations (WAF block decisions, OWASP rule matches, rate limits) are recorded inside **Application Load Balancer request logs**: `http_load_balancer` for the global external load balancer, `http_external_regional_lb_rule` for regional external and `internal_http_lb_rule` for internal ones. This deployment routes all three.

<walkthrough-info-message>**Crucial Check Before Proceeding:**
If backend service request logging is disabled, Cloud Armor decisions are **not written** to Cloud Logging and will never reach Abstract.</walkthrough-info-message>

Inspect existing backend services in your workload projects:

```bash
# Check if logging is enabled on your backend services:
gcloud compute backend-services list --format="table(name,enableLogging,logConfig.sampleRate)"
```

To enable logging on a backend service with 100% sample rate:

```bash
# Global backend service:
gcloud compute backend-services update BACKEND_SERVICE_NAME \
  --global \
  --enable-logging \
  --logging-sample-rate=1.0

# Regional backend service:
gcloud compute backend-services update BACKEND_SERVICE_NAME \
  --region=REGION \
  --enable-logging \
  --logging-sample-rate=1.0
```

## Step 2 — Verify Cloud IDS Endpoints

> [!NOTE]
> **Cloud IDS costs money on its own.** It is billed per endpoint-hour plus per GB of traffic inspected, and it needs Packet Mirroring. These templates do not create the IDS endpoint or the mirroring policy; they only route the threat logs an existing endpoint writes.

Cloud IDS uses Palo Alto Networks threat detection engines to analyze mirrored network traffic for malware, spyware, and exploit CVEs.

Check whether Cloud IDS endpoints are provisioned in your workload VPCs:

```bash
gcloud ids endpoints list
```

If you do not have an active Cloud IDS endpoint, you can create one with `INFORMATIONAL` severity to log all threat severities:

```bash
# 1. Create the endpoint (takes ~15 minutes to provision):
gcloud ids endpoints create ids-us-central1 \
  --zone=us-central1-a \
  --network=VPC_NETWORK_NAME \
  --severity=INFORMATIONAL

# 2. Get the collector forwarding rule:
FORWARDING_RULE=$(gcloud ids endpoints describe ids-us-central1 \
  --zone=us-central1-a \
  --format="value(endpointForwardingRule)")

# 3. Create a packet mirroring policy to mirror traffic to the IDS collector:
gcloud compute packet-mirrorings create ids-packet-mirroring \
  --region=us-central1 \
  --network=VPC_NETWORK_NAME \
  --collector-ilb="$FORWARDING_RULE" \
  --mirrored-subnets=MONITORED_SUBNET_NAME
```

When threat signatures match, logs are automatically written to `logName:"ids.googleapis.com%2Fthreat"`.

## Step 3 — Verify Cloud DNS Query Logging

DNS query logging captures lookups from VMs and containers, delivering high-signal detection for C2 beaconing, DGA domains, and DNS tunneling exfiltration.

By default, DNS queries are **not logged** until a Cloud DNS server policy is created.

Check for existing DNS server policies:

```bash
gcloud dns policies list
```

Enable DNS query logging on your VPC network:

```bash
gcloud dns policies create log-vpc-dns-queries \
  --description="Enable DNS query logging for security monitoring" \
  --enable-logging \
  --networks=VPC_NETWORK_NAME
```

Once applied, all queries originating within that VPC are emitted to `logName:"dns.googleapis.com%2Fdns_queries"`.

## Step 4 — Verify Firewall Rule Logging

Firewall rule logging must be enabled on individual VPC firewall rules or within Network Firewall Policies.

Check whether firewall rules have logging enabled:

```bash
gcloud compute firewall-rules list --format="table(name,network,direction,action,logConfig.enable)"
```

Enable logging on critical rules (especially default deny rules):

```bash
gcloud compute firewall-rules update FIREWALL_RULE_NAME \
  --enable-logging \
  --logging-metadata=include-all
```

Matched connections will be emitted to `logName:"compute.googleapis.com%2Ffirewall"`.

## Step 5 — Configure Variables

Initialize your `terraform.tfvars` file:

```bash
cat > terraform.tfvars <<EOF
sink_scope              = "organization"
org_id                  = "$ORG_ID"
log_project             = "$LOG_PROJECT"
log_categories          = ["firewall", "dns_queries", "load_balancer", "load_balancer_regional_internal"]
platform_log_filters    = ["ids.googleapis.com%2Fthreat"]
EOF
```

<walkthrough-info-message>`dns_queries`, `load_balancer` and `load_balancer_regional_internal` (Cloud Armor) are high-volume streams, so the first plan stops on purpose. Measure a baseline first; then add `acknowledge_high_volume = true` to `terraform.tfvars`, or pass `terraform plan -var acknowledge_high_volume=true`.</walkthrough-info-message>

## Step 6 — Plan and Apply

Initialize the Terraform working directory and inspect the execution plan:

```bash
terraform init
terraform plan
```

Review the `effective_filter` displayed in the plan. It binds all four telemetry streams into one aggregated Cloud Logging sink.

Apply the configuration:

```bash
terraform apply
```

Inspect output parameters:

```bash
terraform output -raw sink_writer_identity
terraform output -raw topic_id
```

## Step 7 — Wait Before You Verify

<walkthrough-info-message>**Log sinks evaluate routing at write time.** Google Cloud takes 2 to 3 minutes to propagate a new aggregated sink across the fleet. Events emitted in the first minutes before propagation finishes will not be captured.</walkthrough-info-message>

Wait 3 minutes before testing:

```bash
echo "Waiting for Log Router sink propagation..."
sleep 180
```

## Step 8 — Verify the Pipeline & Troubleshooting

### 1. Check the Log Sink and Aggregation

Verify that the sink exists and `includeChildren` is `True`:

```bash
gcloud logging sinks describe abstract-network-threats-sink \
  --organization="$ORG_ID" \
  --format="value(name,includeChildren,destination)"
```

### 2. Check Publisher IAM Permissions (The #1 Silent Failure Mode)

Verify that the sink's writer identity holds `roles/pubsub.publisher` on the topic:

```bash
gcloud pubsub topics get-iam-policy abstract-network-threats \
  --project="$LOG_PROJECT" \
  --filter="bindings.role:roles/pubsub.publisher"
```

If the writer identity is missing from the output, grant it:
```bash
WRITER_SA=$(terraform output -raw sink_writer_identity)
gcloud pubsub topics add-iam-policy-binding abstract-network-threats \
  --project="$LOG_PROJECT" \
  --member="${WRITER_SA}" \
  --role="roles/pubsub.publisher"
```

### 3. Check for Sink Delivery Errors

Confirm that no sink errors are reported:

```bash
gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' \
  --project="$LOG_PROJECT" \
  --limit=10
```

### 4. End-to-End Delivery Test

Create a probe subscription, then perform a DNS query or trigger a firewall probe from a VM in your VPC:

```bash
# Never pull from abstract-network-threats-sub: with --auto-ack that deletes events before Abstract
# reads them, and without it hides them from Abstract for the ack deadline.
# Pull from a throwaway subscription on the same topic instead. Create it BEFORE the
# test event: a new subscription only receives messages published after it exists.
PROBE="abstract-probe-$(date +%s)"
gcloud pubsub subscriptions create "$PROBE" --topic=abstract-network-threats \
  --project="$LOG_PROJECT" --expiration-period=1d --message-retention-duration=10m
# Now make a DNS query or trigger a logged firewall rule from a VM, then wait.
sleep 60
gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=5 --auto-ack
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

## Step 9 — Connect to Abstract Security

Extract the integration parameters:

```bash
terraform output abstract_onboarding
```

Generate the credentials key for the Abstract service account:

```bash
SA_EMAIL=$(terraform output -raw service_account_email)
mkdir -p ~/abstract-keys && chmod 700 ~/abstract-keys   # outside the repo clone
gcloud iam service-accounts keys create ~/abstract-keys/abstract-network-key.json --iam-account="$SA_EMAIL"
chmod 600 ~/abstract-keys/abstract-network-key.json
```

In the Abstract Security Platform:
1. Navigate to **Data Sources** → **Add Data Source** → **Google Cloud Pub/Sub**.
2. Enter the **Project ID** (`$LOG_PROJECT`).
3. Enter the **Subscription ID**:
   ```bash
   terraform output -raw subscription_id
   ```
4. Upload `~/abstract-keys/abstract-network-key.json`.
5. Remove the local key file:
   ```bash
   rm -f ~/abstract-keys/abstract-network-key.json
   ```

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

The pipeline delivers Cloud Armor, Cloud IDS, DNS and firewall logs to the `abstract-network-threats` topic. Abstract's managed GCP parser does not yet store these logs, so do not rely on them for detection until a parser ships.

---

<sub>**Abstract Security · GCP Network Threats** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
