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

## Before you start

<walkthrough-project-setup></walkthrough-project-setup>

You need the following permissions:

1. **`roles/logging.configWriter` at ORGANIZATION or FOLDER scope**: Required to create the aggregated log sink across your estate.
2. **`roles/pubsub.admin`** on the logging project: To manage the Pub/Sub topic and subscription.
3. **`roles/iam.serviceAccountAdmin`** on the logging project: To create the Abstract subscriber identity.

<walkthrough-info-message>Always use a **dedicated logging project** rather than a workload project. Workload owners should not possess access to read or modify security pipelines, and Pub/Sub quota is consumed in this project.</walkthrough-info-message>

<!-- abstract:signin -->
## Sign in first

Cloud Shell opened the public templates repository in a **temporary** session. Google gives a repository it does not own none of your credentials, and deletes the session's files when it ends. Sign in; `--update-adc` gives the scripts and Terraform the same sign-in:

```bash
gcloud auth login --update-adc
```
<!-- /abstract:signin -->

<!-- abstract:check -->
## Check first

Read-only: nothing changes. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script steps 1 and 2 of the guided setup record your scope and check the rights the sink needs; script step 3 checks the logging project, and the organization policy that can block the service-account key.

```bash
cd "$(git rev-parse --show-toplevel)"
./tools/gcp-guided-setup/audit-gcp-estate.sh
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 2
```

If a permission row shows ✗, find the person who holds that role before you go on.

The guided setup saves your answers (organization, scope, logging project, topic, subscription). Load them for the commands on this page:

```bash
source ~/.abstract-gcp-setup.env
```
<!-- /abstract:check -->

## Verify Cloud Armor Logging

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

## Verify Cloud IDS Endpoints

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

## Verify Cloud DNS Query Logging

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

## Verify Firewall Rule Logging

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

## Choose the log categories

Set these in terraform.tfvars:

```hcl
sink_scope           = "organization"
log_categories       = ["firewall", "dns_queries", "load_balancer", "load_balancer_regional_internal"]
platform_log_filters = ["ids.googleapis.com%2Fthreat"]
```

<walkthrough-info-message>`dns_queries`, `load_balancer` and `load_balancer_regional_internal` (Cloud Armor) are high-volume streams, so the first deploy stops on purpose. Measure a baseline first; then add `acknowledge_high_volume = true` to `terraform.tfvars`.</walkthrough-info-message>

Read the `effective_filter` before you apply. It binds all four telemetry streams into one aggregated Cloud Logging sink.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

<walkthrough-info-message>**Log sinks evaluate routing at write time.** Google Cloud takes 2 to 3 minutes to propagate a new aggregated sink across the fleet. Events emitted in the first minutes before propagation finishes will not be captured.</walkthrough-info-message>

Inspect output parameters:

```bash
terraform output -raw sink_writer_identity
terraform output -raw topic_id
```

Wait 3 minutes before testing:

```bash
echo "Waiting for Log Router sink propagation..."
sleep 180
```

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
for i in $(seq 1 20); do
  sleep 15
  N=$(gcloud pubsub subscriptions pull "$PROBE" --project="$LOG_PROJECT" --limit=1000 --auto-ack --format="value(ackId)" 2>/dev/null | grep -c .)
  [ "${N:-0}" -gt 0 ] && { echo "FOUND: $N message(s) reached the topic"; break; }
done
gcloud pubsub subscriptions delete "$PROBE" --project="$LOG_PROJECT" --quiet
```

## Connect to Abstract Security

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

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then follow **To remove it later** at the end of [Deploy with Terraform](#deploy-with-terraform), with the same `backend.tf`.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=<project-id-with-billing>` to put the bucket in a project that has it.

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
source ~/.abstract-gcp-setup.env 2>/dev/null   # the guided setup's saved answers, if you ran it
echo "Logging project: ${LOG_PROJECT:?not set: run export LOG_PROJECT=<your-logging-project-id> first}"
export STATE_PROJECT="${STATE_PROJECT:-$LOG_PROJECT}" STATE_BUCKET="$LOG_PROJECT-abstract-tfstate"
gcloud storage buckets describe "gs://$STATE_BUCKET" >/dev/null 2>&1 || \
  gcloud storage buckets create "gs://$STATE_BUCKET" --project="$STATE_PROJECT" --location=US --uniform-bucket-level-access
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
sed "s/acme-abstract-tfstate/$STATE_BUCKET/" backend.tf.example > backend.tf
```

**2. Fill in your values.** Every value is explained in the file and in this template's README:

```bash
cp terraform.tfvars.example terraform.tfvars
cloudshell edit terraform.tfvars
```

**3. Preview, then apply exactly what you previewed:**

```bash
terraform init
terraform plan -out=abstract.tfplan
terraform apply abstract.tfplan
```

**To remove it later**, delete the integration in Abstract first. The topic, the subscription and the sink carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the sink first so nothing is written to a topic that is about to go, then the subscription, then the topic. Use your own names if you changed them in terraform.tfvars:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_organization_sink.abstract[0]'
terraform destroy
gcloud logging sinks delete abstract-network-threats-sink --organization=<org-id>
gcloud pubsub subscriptions delete abstract-network-threats-sub --project=<log-project-id>
gcloud pubsub topics delete abstract-network-threats --project=<log-project-id>
```

These commands are for the default `sink_scope`, `organization`. With another scope, use that scope's sink in both places: `'module.log_export.google_logging_folder_sink.abstract[0]'` and `--folder=<folder-id>`; `'module.log_export.google_logging_project_sink.abstract[0]'` and `--project=<sink-project-id>`.
<!-- /abstract:terraform -->

<!-- abstract:references -->
## Google documentation

Google's own pages on what this template sets up:

- [VPC firewall rules logging overview](https://docs.cloud.google.com/firewall/docs/vpc-firewall-rules-logging-overview)
- [Manage VPC firewall rules logging](https://docs.cloud.google.com/firewall/docs/manage-vpc-firewall-rules-logging#enable-vpc-firewall-rule-logging)
- [Firewall policy rules logging overview](https://docs.cloud.google.com/firewall/docs/firewall-policy-rules-logging-overview)
- [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging)
- [Global external Application Load Balancer logging and monitoring](https://docs.cloud.google.com/load-balancing/docs/https/https-logging-monitoring)
- [Regional external Application Load Balancer logging and monitoring](https://docs.cloud.google.com/load-balancing/docs/https/https-reg-logging-monitoring)
- [Internal Application Load Balancer logging and monitoring](https://docs.cloud.google.com/load-balancing/docs/l7-internal/monitoring)
- [Cloud IDS logging information](https://docs.cloud.google.com/intrusion-detection-system/docs/logging)
- [Collate and route organization- and folder-level logs to supported destinations](https://docs.cloud.google.com/logging/docs/export/aggregated_sinks#aggregated-sinks)
- [Logging query language](https://docs.cloud.google.com/logging/docs/view/logging-query-language)
<!-- /abstract:references -->

---

<sub>**Abstract Security · GCP Network Threats** — [all scenarios](../../../README.md) · [architecture](../../../docs/gcp/ARCHITECTURE.md) · [permissions](../../../docs/gcp/PERMISSIONS.md) · [filters](../../../docs/gcp/FILTERS.md)</sub>
