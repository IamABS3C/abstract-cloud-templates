<img src="../../../docs/brand/abstract-logo-white.svg" alt="Abstract Security" width="150">

# Export network threat logs (not kept by Abstract yet)

<walkthrough-tutorial-duration duration="20"></walkthrough-tutorial-duration>

> [!WARNING]
> **Abstract does not keep these logs today. Deploying this template costs money in Google Cloud and adds nothing in Abstract until Abstract's Google Cloud integration supports these records.** Abstract's Google Cloud Pub/Sub integration keeps only Cloud Audit Log records, and firewall, Cloud DNS, load balancer (Cloud Armor) and Cloud IDS logs are not audit logs.

<!-- abstract:needs -->
**This page uses Terraform, because the guided setup script builds only the audit-log sink, and this is a second sink with its own filter and topic.**

Needs: Terraform (Cloud Shell has it), a Cloud Storage bucket for its state (the Terraform section creates it), and the roles under [Check first](#check-first). [Deploy with Terraform](#deploy-with-terraform), at the end of this page, deploys it.
<!-- /abstract:needs -->

This template adds a second, filtered sink that routes four kinds of network log to their own Pub/Sub topic,
abstract-network-threats, in your logging project:

1. **Cloud Armor decisions**, inside Application Load Balancer request logs (`resource.type` `http_load_balancer`, `http_external_regional_lb_rule` and `internal_http_lb_rule`)
2. **Cloud IDS threat logs** (`logName:"ids.googleapis.com%2Fthreat"`)
3. **Cloud DNS query logs** (`logName:"dns.googleapis.com%2Fdns_queries"`)
4. **Firewall rule logs** (`logName:"compute.googleapis.com%2Ffirewall"`)

A sink only routes what Google already writes. Each of these sources is off until the team that owns the network
or the service turns it on, at its own source, and each adds log volume Google bills. This page checks each one,
read-only, and links Google's page for turning it on; it never changes them. Whether each is turned on per project,
per network or for the whole organization is in [Where each source is turned on](../../../docs/gcp/FILTERS.md#where-each-source-is-turned-on).

## Before you start

You need the following permissions:

1. **`roles/logging.configWriter` at ORGANIZATION or FOLDER scope**: to create the aggregated log sink.
2. **`roles/pubsub.admin`** on the logging project: to manage the Pub/Sub topic and subscription.
3. **`roles/iam.serviceAccountAdmin`** on the logging project: to create the Abstract subscriber identity.

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

Read-only, except the role grants at the end, which say what they add. The estate audit lists your organization, folders, projects, and the log sinks and topics you already have. Script step 1 of the guided setup records your organization and scope (ORG_ID, SCOPE_ID) in its answers file, `~/.abstract-gcp-setup.env`.

Go to the top folder of the templates repository; the guided-setup commands run from there:

```bash
cd "$(git rev-parse --show-toplevel)"
```

List what you already have (read-only):

```bash
./tools/gcp-guided-setup/audit-gcp-estate.sh
```

Script step 1: your organization and scope.

```bash
./tools/gcp-guided-setup/abstract-gcp-setup.sh --step 1
```

Load the answers into this terminal. It sets ORG_ID, and LOG_PROJECT if you ran the guided setup's script step 3 before:

```bash
source ~/.abstract-gcp-setup.env
```

This page also needs your logging project, the project that holds the topic and subscription. Check both are set. You should see your organization's number and your logging project's ID; "not set" names what to do:

```bash
echo "Organization: ${ORG_ID:?not set: run script step 1} Logging project: ${LOG_PROJECT:?not set: export LOG_PROJECT=LOGGING_PROJECT_ID}"
```

Only if it said the logging project is not set (you have not run script step 3): set it yourself, replacing LOGGING_PROJECT_ID with its ID, then run the check above again:

```bash
export LOG_PROJECT=LOGGING_PROJECT_ID
```

### The roles this page needs

The guided setup's own grant option covers only the roles its script steps need, not these. The person who deploys this template needs:

- `roles/logging.configWriter` on the organization (or the folder or project for those scopes): Create the sink.
- `roles/pubsub.admin` on the logging project: Create the topic, subscription and IAM bindings.
- `roles/iam.serviceAccountAdmin` on the logging project: Create Abstract's service account.
- `roles/serviceusage.serviceUsageAdmin` on the logging project: Turn on the APIs this template uses. Terraform reads which are on and turns on only those still off.

Someone who can set IAM policy there adds each as one binding; nothing else in the policy changes. Replace PRINCIPAL with the person who deploys: `user:` and their email, `group:` and a group's email, or `serviceAccount:` and a service account's email.

Add `roles/logging.configWriter` for PRINCIPAL on your organization (ORG_ID):

```bash
gcloud organizations add-iam-policy-binding "$ORG_ID" --member="PRINCIPAL" --role="roles/logging.configWriter" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud organizations remove-iam-policy-binding "$ORG_ID" --member="PRINCIPAL" --role="roles/logging.configWriter" --condition=None
```

For a folder or project sink, grant it there instead: `gcloud resource-manager folders add-iam-policy-binding FOLDER_ID` or `gcloud projects add-iam-policy-binding PROJECT_ID`, with the same `--member` and `--role`.

Add `roles/pubsub.admin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/pubsub.admin" --condition=None
```

Add `roles/iam.serviceAccountAdmin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/iam.serviceAccountAdmin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/iam.serviceAccountAdmin" --condition=None
```

Add `roles/serviceusage.serviceUsageAdmin` for PRINCIPAL on your logging project (LOG_PROJECT):

```bash
gcloud projects add-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
```

To take it back once the deploy is done (this removes only that binding):

```bash
gcloud projects remove-iam-policy-binding "$LOG_PROJECT" --member="PRINCIPAL" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
```

Removing this template later (**To remove it later**, at the end of the page) needs these roles again: add them back with the same commands first.
<!-- /abstract:check -->

## Find the projects and networks to check

The checks below run against one workload project at a time: a project that runs load balancers, VMs or
containers. Replace WORKLOAD_PROJECT_ID in each command with its ID.

If gcloud offers to enable an API ("API [...] not enabled on project [...]. Would you like to enable and retry?"),
answer **N**: the API being off means the source is not set up there, which is the answer you came for. Answering y would turn the API on in a project that is not yours to change, and for Compute Engine
it would also create that project's default network, with firewall rules that allow SSH and RDP from anywhere.

List the projects you can see, with their IDs (read-only):

```bash
gcloud projects list --format='table(projectId,name)'
```

List the VPC networks in one of them (read-only):

```bash
gcloud compute networks list --project=WORKLOAD_PROJECT_ID
```

## Check load balancer logging (Cloud Armor)

Cloud Armor's decisions (WAF blocks, rule matches, rate limits) are written inside the Application Load Balancer's
request logs, so they exist only when request logging is on for the backend service. Google turns it on per backend
service; the person who owns the load balancer decides, because it adds log volume billed by Cloud Logging.

List the backend services in the project with their logging setting (read-only). True under ENABLE means request logs, Cloud Armor decisions included, are written; False or empty means they are not:

```bash
gcloud compute backend-services list --project=WORKLOAD_PROJECT_ID --format="table(name,region.basename(),logConfig.enable:label=ENABLE,logConfig.sampleRate)"
```

Turning it on is the load balancer owner's decision: [Global external Application Load Balancer logging and monitoring](https://docs.cloud.google.com/load-balancing/docs/https/https-logging-monitoring),
[Regional external Application Load Balancer logging and monitoring](https://docs.cloud.google.com/load-balancing/docs/https/https-reg-logging-monitoring)
and [Internal Application Load Balancer logging and monitoring](https://docs.cloud.google.com/load-balancing/docs/l7-internal/monitoring).
Once it is on, this template's `load_balancer` and `load_balancer_regional_internal` categories route those logs.

## Check Cloud IDS

Cloud IDS inspects mirrored traffic for malware, spyware and exploits. It needs an IDS endpoint in each region you
monitor and a packet-mirroring policy that copies traffic to it; both are billed, and both change the network, so
they are the network owner's decision. These templates create neither.

If gcloud offers to enable the Cloud IDS API, answer **N**: off means Cloud IDS is not set up there. List the IDS
endpoints in the project (read-only). An endpoint in state READY is inspecting traffic; an empty list means Cloud IDS is not set up there:

```bash
gcloud ids endpoints list --project=WORKLOAD_PROJECT_ID
```

To set it up, see [Cloud IDS overview](https://docs.cloud.google.com/intrusion-detection-system/docs/overview);
the threat logs it writes are described in [Cloud IDS logging information](https://docs.cloud.google.com/intrusion-detection-system/docs/logging).
Once an endpoint is running, this template's `platform_log_filters` entry `ids.googleapis.com%2Fthreat` routes its threat logs.

## Check Cloud DNS query logging

DNS query logs show the lookups VMs and containers make, the trail of command-and-control beacons and DNS
tunnelling. Google writes them only for a VPC network with a DNS server policy that has logging on (or for a public
zone with query logging on), and they add log volume billed by Cloud Logging.

If gcloud offers to enable the Cloud DNS API, answer **N**: off means no DNS policy is set up there. List the DNS
server policies in the project and whether each logs queries (read-only). True under ENABLELOGGING, for a policy attached to a network, means that network's queries are logged; no policy, or False, means they are not:

```bash
gcloud dns policies list --project=WORKLOAD_PROJECT_ID --format="table(name,enableLogging,networks[].networkUrl.basename())"
```

Turning it on is the network owner's decision: [Use logging and monitoring](https://docs.cloud.google.com/dns/docs/monitoring#using_logging).
Once it is on, this template's `dns_queries` category routes those logs.

## Check firewall rule logging

Firewall logs record the connections a rule allowed or denied. Google turns logging on per rule: on each VPC
firewall rule in a project, and on each rule of a hierarchical firewall policy at an organization or folder. Each
logged rule adds log volume billed by Cloud Logging, so the network owner chooses which rules to log.

List the VPC firewall rules in the project and whether each is logged (read-only). True under LOGGED means that rule's hits are logged; False or empty means they are not:

```bash
gcloud compute firewall-rules list --project=WORKLOAD_PROJECT_ID --format="table(name,network.basename(),direction,logConfig.enable:label=LOGGED)"
```

List the hierarchical firewall policies at the organization (read-only; ORG_ID comes from the answers file loaded above):

```bash
gcloud compute firewall-policies list --organization="$ORG_ID"
```

List one policy's rules and whether each is logged (read-only). Replace POLICY_ID with an ID from the list above:

```bash
gcloud compute firewall-policies list-rules POLICY_ID --organization="$ORG_ID" --format="table(priority,action,direction,enableLogging)"
```

Turning it on is the network owner's decision: [Manage VPC firewall rules logging](https://docs.cloud.google.com/firewall/docs/manage-vpc-firewall-rules-logging#enable-vpc-firewall-rule-logging)
and [Firewall policy rules logging overview](https://docs.cloud.google.com/firewall/docs/firewall-policy-rules-logging-overview).
Once it is on, this template's `firewall` category routes those logs.

## Choose the log categories

If you still deploy it, knowing Abstract keeps none of it today, choose which of the four streams the sink routes:
`firewall`, `dns_queries`, `load_balancer` and `load_balancer_regional_internal` (Cloud Armor, global and regional),
and the Cloud IDS threat logs. Deploy with Terraform, step 2, says where each goes.

<walkthrough-info-message>`dns_queries`, `load_balancer` and `load_balancer_regional_internal` (Cloud Armor) are high-volume streams, so the first deploy stops on purpose until you acknowledge the volume. Measure a baseline first.</walkthrough-info-message>

Measure a baseline: count one hour of one stream in one workload project (read-only; it stops at 10,000 entries, so
10000 means at least that many an hour). Replace WORKLOAD_PROJECT_ID, and LOG_FILTER with the stream's filter:
`logName:"compute.googleapis.com%2Ffirewall"` for firewall, `logName:"dns.googleapis.com%2Fdns_queries"` for DNS,
`resource.type="http_load_balancer"` for the global load balancer, `logName:"ids.googleapis.com%2Fthreat"` for Cloud IDS:

```bash
gcloud logging read 'LOG_FILTER' --project=WORKLOAD_PROJECT_ID --freshness=1h --limit=10000 --format='value(timestamp)' | wc -l
```

Multiply by 24 for a day and by the number of projects that log the stream. Cloud Logging bills the volume a sink
routes on top of what each project already stores, so this is the number the network owner signs off.

Read the `effective_filter` before you apply: it is the one filter the new sink uses for all four streams.

<!-- abstract:deploy -->
## Deploy

This piece is not part of the guided setup script. Deploy it with Terraform: follow [Deploy with Terraform](#deploy-with-terraform) at the end of this page, then come back here to verify.
<!-- /abstract:deploy -->

## Verify

<walkthrough-info-message>**Log sinks evaluate routing at write time.** A new sink routes nothing for about three minutes. Events written before then are not routed, and no later change recovers them.</walkthrough-info-message>

Wait three minutes after the apply. These checks read, and change nothing, except where a command says otherwise.

In this template's folder, print the sink's writer identity:

```bash
terraform output -raw sink_writer_identity
```

The sink exists and is aggregated: you should see abstract-network-threats-sink, True, and the topic. This is the
organization sink; with `sink_scope = "folder"` use `--folder=FOLDER_ID` instead of `--organization`, and with
`"project"` use `--project=PROJECT_ID`:

```bash
gcloud logging sinks describe abstract-network-threats-sink --organization="$ORG_ID" --format="value(name,includeChildren,destination)"
```

The writer identity holds roles/pubsub.publisher on the topic, the most common silent failure. You should see the identity printed above under roles/pubsub.publisher:

```bash
gcloud pubsub topics get-iam-policy abstract-network-threats --project="$LOG_PROJECT"
```

If it is missing, run `terraform apply` again: the template grants it. Google records a sink's delivery failures as
log entries; nothing printed means none was recorded:

```bash
gcloud logging read 'logName:"logging.googleapis.com%2Fsink_error"' --project="$LOG_PROJECT" --limit=10
```

## Connect to Abstract

Not yet. Abstract's Google Cloud integration keeps only Cloud Audit Logs, so a Pub/Sub source on
abstract-network-threats-sub would read these logs and discard them. When Abstract supports them, the values come from
`terraform output abstract_onboarding` in this template's folder.

## Done

<walkthrough-conclusion-trophy></walkthrough-conclusion-trophy>

The sink routes the network logs whose sources are turned on to the `abstract-network-threats` topic. Abstract does
not keep them today; remove the template (below) if you deployed it only for Abstract.

<!-- abstract:cleanup -->
## Clean up

Delete the integration in Abstract first, if this piece feeds one. Then follow **To remove it later** at the end of [Deploy with Terraform](#deploy-with-terraform), with the same `backend.tf`.
<!-- /abstract:cleanup -->

<!-- abstract:terraform -->
## Deploy with Terraform

Run every command in this template's folder.

**1. Keep the state outside this session.** Cloud Shell deletes its files when the session ends, state included. Create a versioned bucket in your logging project once, and point `backend.tf` at it. The state key in `backend.tf.example` is fixed: do not change it. The bucket goes in the logging project by default, and Google's Cloud Storage guides ask for billing on a project before you create a bucket in it (this repo has not tested a project without). If the logging project has no billing (the guided setup allows that), first run `export STATE_PROJECT=PROJECT_ID_WITH_BILLING`, with your own project ID, to put the bucket in a project that has it.

Go to this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
```

Load the guided setup's answers, if you ran it (it sets LOG_PROJECT and ORG_ID):

```bash
source ~/.abstract-gcp-setup.env
```

Check the logging project is set. If it says not set, run `export LOG_PROJECT=` and your logging project ID first:

```bash
echo "Logging project: ${LOG_PROJECT:?not set}"
```

Name the state bucket, in the logging project unless STATE_PROJECT is set:

```bash
export STATE_PROJECT="${STATE_PROJECT:-$LOG_PROJECT}" STATE_BUCKET="$LOG_PROJECT-abstract-tfstate"
```

Choose where the state bucket lives. Replace LOCATION with a Cloud Storage location your organization allows ([Bucket locations](https://docs.cloud.google.com/storage/docs/locations) lists them): the multi-region or region your data-residency rules name. An organization policy on resource locations refuses any other. A state bucket you created before stays where it is; this does not move it:

```bash
export STATE_LOCATION=LOCATION
```

Create the bucket, in STATE_PROJECT at STATE_LOCATION (to undo it once nothing uses the state, delete the bucket). If you made it before, Google answers that it already exists; go on:

```bash
gcloud storage buckets create "gs://$STATE_BUCKET" --project="$STATE_PROJECT" --location="$STATE_LOCATION" --uniform-bucket-level-access
```

Keep every version of the state:

```bash
gcloud storage buckets update "gs://$STATE_BUCKET" --versioning
```

Point `backend.tf` at the bucket:

```bash
sed "s/acme-abstract-tfstate/$STATE_BUCKET/" backend.tf.example > backend.tf
```

**2. Fill in your values.**

Copy the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Each value is described in the file. The required ones are not commented out, and hold an UPPERCASE placeholder until you replace it. Terraform does not notice one left behind, so **3. Preview** below checks for them before the plan.

Replace:

- `log_project`: your logging project ID (LOG_PROJECT; `echo "$LOG_PROJECT"` prints it)

Edit it in Cloud Shell's editor:

```bash
cloudshell edit terraform.tfvars
```
<!-- /abstract:terraform -->

Set the scope and the streams, with ORG_ID your organization's ID. Keep only the streams whose source is turned on:

```hcl
sink_scope           = "organization"
org_id               = "ORG_ID"
log_categories       = ["firewall", "dns_queries", "load_balancer", "load_balancer_regional_internal"]
platform_log_filters = ["ids.googleapis.com%2Fthreat"]
```

For a folder sink set `sink_scope = "folder"` and `folder_id` instead of `org_id`. With `dns_queries`,
`load_balancer` or `load_balancer_regional_internal`, the first plan stops on purpose: once the baseline is measured
and signed off, add `acknowledge_high_volume = true`.

<!-- abstract:tfapply -->
**3. Preview, then apply exactly what you previewed.**

Check no placeholder is left (read-only). You should see nothing; a line it prints still holds a placeholder, so replace it in terraform.tfvars and run this again:

```bash
grep -nE '^[^#]*\b(LOGGING_PROJECT_ID|ORG_ID)\b' terraform.tfvars
```

Download the providers and connect to the state bucket:

```bash
terraform init
```

Preview, and save the plan. It ends with the outputs, `effective_filter` among them: the filter the sink will use, which decides your coverage and your bill:

```bash
terraform plan -out=abstract.tfplan
```

Apply exactly that plan. It creates what the plan listed; **To remove it later**, below, says how to take it away:

```bash
terraform apply abstract.tfplan
```

Print the filter the sink uses (read-only). You should see one Cloud Logging filter, naming the sources you chose in `log_categories` and `platform_log_filters`, and no audit logs (`cloudaudit.googleapis.com`): `audit_streams` is empty here because the audit-log templates route those, and adding them would send a second copy, billed again; it is the filter that decides your coverage and your bill:

```bash
terraform output -raw effective_filter
```
<!-- /abstract:tfapply -->

<!-- abstract:tfremove -->
**To remove it later**, delete the integration in Abstract first. The topic, the subscription and the sink carry `prevent_destroy`, so a stray `terraform destroy`, or a rename that would replace them, cannot drop security logs Abstract has not read yet; `terraform destroy` on its own is refused. Take them out of the state, destroy the rest, then delete them with gcloud, the sink first so nothing is written to a topic that is about to go, then the subscription, then the topic. Use your own names if you changed them in terraform.tfvars.

The commands below use the guided setup's answers (LOG_PROJECT, ORG_ID, SCOPE_ID), saved in `~/.abstract-gcp-setup.env`. Load them in this terminal; without the guided setup, `export` each one instead:

```bash
source ~/.abstract-gcp-setup.env
```

In this template's folder:

```bash
cd "$(git rev-parse --show-toplevel)/templates/gcp/gcp-source-network-threat-logs"
```

Take them out of the state (this deletes nothing):

```bash
terraform state rm 'module.log_export.google_pubsub_topic.abstract' 'module.log_export.google_pubsub_subscription.abstract' 'module.log_export.google_logging_organization_sink.abstract[0]'
```

Destroy the rest of what this template built (Terraform lists it and asks first):

```bash
terraform destroy
```

Delete the sink abstract-network-threats-sink, so nothing more is written to the topic:

```bash
gcloud logging sinks delete abstract-network-threats-sink --organization="$ORG_ID" --quiet
```

Delete the subscription abstract-network-threats-sub, and every event in it not yet read:

```bash
gcloud pubsub subscriptions delete abstract-network-threats-sub --project="$LOG_PROJECT" --quiet
```

Delete the topic abstract-network-threats:

```bash
gcloud pubsub topics delete abstract-network-threats --project="$LOG_PROJECT" --quiet
```

These commands are for the default `sink_scope`, `organization`. With another scope, use that scope's sink in both places: `'module.log_export.google_logging_folder_sink.abstract[0]'` and `--folder="$SCOPE_ID"`; `'module.log_export.google_logging_project_sink.abstract[0]'` and `--project="$SCOPE_ID"`.
<!-- /abstract:tfremove -->

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
