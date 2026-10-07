# Guides

**Start with the setup guide for your cloud.** A few questions lead to one plan: every step in order,
who does it and where, from checking what you already have to cleaning it all up.

- [Set up AWS](aws/GUIDE.md)
- [Set up Microsoft Azure](azure/GUIDE.md)
- [Set up Google Cloud](gcp/GUIDE.md)

Each template's own README covers what it creates, what it needs and how to deploy it. The pages below
go deeper on what spans templates: architecture, permissions and troubleshooting.

## AWS

| Guide | Read it when |
|---|---|
| [The options explained](aws/OPTIONS.md) | You want to know why S3 → SQS, SNS fan-out or EventBridge, and what surprises people |
| [Sources and parameters](aws/SOURCES.md) | You want guidance per log source, or every parameter of every template |
| [Architecture](aws/ARCHITECTURE.md) | You want the S3 and SQS design, and why |
| [Deployment](aws/DEPLOYMENT.md) | You deploy by script, by StackSet or with your own template copies |
| [Security](aws/SECURITY.md) | Your security team reviews what Abstract can reach |
| [Roadmap](aws/ROADMAP.md) | You want to know what is coming for AWS |

## Azure

| Guide | Read it when |
|---|---|
| [Log streams](azure/azure-log-streams.md) | You plan how Azure logs reach the Event Hub |
| [App registrations](azure/azure-app-registrations.md) | You choose how Abstract signs in to your tenant |
| [Sentinel destination assurance](azure/sentinel-destination-assurance.md) | You send Abstract data on to Microsoft Sentinel, and want to know what each option asks of your tenant |
| [Sentinel and ASIM](azure/sentinel-asim.md) | You want Abstract data in Sentinel's normalised (ASIM) schema |

## Google Cloud

| Guide | Read it when |
|---|---|
| [Setup](gcp/SETUP.md) | You start a Google Cloud onboarding |
| [Architecture](gcp/ARCHITECTURE.md) | You want the sink, Pub/Sub and subscription design |
| [Permissions](gcp/PERMISSIONS.md) | You need to know who needs which role, and why |
| [Filters](gcp/FILTERS.md) | You tune which logs the sink sends |
| [Deploy from Cloud Shell](gcp/DEPLOY-CLOUD-SHELL.md) | You deploy with the Open in Cloud Shell buttons |
| [Deploy with Infrastructure Manager](gcp/DEPLOY-INFRA-MANAGER.md) | You deploy through Google's managed Terraform service |
| [Scripts](gcp/SCRIPTS.md) | You use the guided setup and helper scripts |
| [The data flow](gcp/DATAFLOW.md) | You want to know how each log source reaches Abstract, hop by hop |
| [Troubleshooting](gcp/TROUBLESHOOTING.md) | The feed is quiet, short or stopped |
| [Identity logs](gcp/IDENTITY.md) | You need sign-in, impersonation or federation events |
| [Abstract integration](gcp/ABSTRACT-INTEGRATION.md) | You connect the subscription to Abstract |
| [Google Workspace](gcp/WORKSPACE.md) | You onboard Workspace audit logs |
| [VPC Service Controls](gcp/VPC-SC.md) | Your projects sit inside a service perimeter |
| [What is verified](gcp/VERIFIED.md) | You want to know what has been deployed and checked for real |
