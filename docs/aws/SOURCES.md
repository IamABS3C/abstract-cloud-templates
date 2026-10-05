# Sources & parameter reference

Per-source guidance plus the complete parameter catalog for every template.

---

## Per-source notes (`_snippets/s3-log-source.yaml`, assembled per source)

### CloudTrail
Creates an `AWS::CloudTrail::Trail` when the stack owns the bucket. Native delivery is
Trail → SNS → SQS (`NotificationPath=CloudTrailToSNSToSQS`, forced on for CloudTrail).
- **Basic:** management events only (`CtIncludeManagementEvents=true`,
  `CtManagementReadWriteType=All`).
- **Advanced:** add S3/Lambda **data events** (high volume/cost), **Insights**
  (`ApiCallRate`/`ApiErrorRate`), multi-region, organization trail, log-file validation.
- Org trail: set `CtIsOrganizationTrail=true` + `CtOrganizationId=o-xxxx` in the
  management/delegated account.
- **Multi-region requires global service events.** AWS rejects a multi-region trail with
  global events off ("Multi-Region trail must include global service events"). The template
  forces `IncludeGlobalServiceEvents=true` whenever `CtIsMultiRegion=true`, and a pre-deploy
  Rule blocks the invalid combination, so this error can't occur.
- **Insights need management events.** Insights are computed from management activity; a Rule
  requires `CtIncludeManagementEvents=true` when `CtEnableInsights=true`.
- **Selectors are independent.** You can log data events with management events off (and vice
  versa); with none selected, CloudTrail's default management logging applies.
- **Existing KMS key:** if you point the trail at a `UseExisting` CMK, that key's policy must
  already allow `cloudtrail.amazonaws.com` to `GenerateDataKey*`/`Decrypt`, or trail creation
  fails (the template can only set the policy on a key it creates).

### CloudFront
Standard logging delivers to S3. Principal `delivery.logs.amazonaws.com`; no ACL header.
After deploy, point the distribution's standard logging at the bucket (CloudFront
distributions aren't created here). Path `S3ToSQS`.

### Load Balancer (ALB/NLB/CLB)
Access logs to S3 via `logdelivery.elasticloadbalancing.amazonaws.com` (ACL header
required). Enable access logging on the LB attributes pointing at the bucket. Path
`S3ToSQS`.

### Route 53 Resolver
Creates the Resolver query-logging config and associates the VPCs in `Route53VpcIds` (when
the stack owns the bucket). Principal `delivery.logs.amazonaws.com`. Path `S3ToSQS`.

### S3 Server Access Logs
This stack provisions the **destination** bucket (principal `logging.s3.amazonaws.com`).
Enable server access logging on your **source** bucket pointing at it. Path `S3ToSQS`.

### VPC Flow Logs
Creates an `AWS::EC2::FlowLog` against `VpcFlowResourceId` (VPC/Subnet/ENI). Options:
`VpcFlowTrafficType` (ALL/ACCEPT/REJECT), `VpcFlowMaxAggregationInterval` (60/600s), and an
optional custom `VpcFlowLogFormat`. Principal `delivery.logs.amazonaws.com`.

### WAF
Bucket name **must** start with `aws-waf-logs-` (the template auto-names it that way). Creates
`AWS::WAFv2::LoggingConfiguration` on `WafWebAclArn`. Principal `delivery.logs.amazonaws.com`.

### Generic S3
Any bucket you write to yourself; principal `s3.amazonaws.com`. Use for custom log shippers.

---

## Universal template — full parameters

### 1. Source selection
| Parameter | Type / values | Default | Notes |
| --- | --- | --- | --- |
| `SourceType` | CloudTrail \| CloudFront \| LoadBalancer \| Route53Resolver \| S3AccessLogs \| VPCFlowLogs \| WAF \| GenericS3 | CloudTrail | Drives principal, ACL default, producer |
| `NamePrefix` | string | abstract | Resource-name prefix |

### 2. Abstract access
| Parameter | Type / values | Default | Notes |
| --- | --- | --- | --- |
| `AuthMode` | AssumeRole \| AccessKey | AssumeRole | |
| `AbstractPrincipalArn` | ARN or 12-digit ID | "" | Required for AssumeRole |
| `ExternalId` | string (NoEcho) | "" | Required for AssumeRole |
| `MaxSessionDurationSeconds` | 900–43200 | 3600 | |
| `PermissionsBoundaryArn` | IAM policy ARN | "" | Optional cap |
| `StoreCredentialsInSecretsManager` | true \| false | false | AccessKey only |
| `ExportToSsm` | true \| false | false | Write outputs to SSM |

### 3. S3 bucket
| Parameter | Type / values | Default | Notes |
| --- | --- | --- | --- |
| `BucketMode` | CreateNew \| UseExisting | CreateNew | |
| `BucketName` | string | "" | Required for UseExisting; optional override for CreateNew |
| `LogPrefix` | string | "" | Scope reads/writes |
| `LogRetentionDays` | 0–3650 | 365 | 0 = keep forever |
| `NoncurrentRetentionDays` | 1–3650 | 30 | |

### 4. Notification
| Parameter | Type / values | Default | Notes |
| --- | --- | --- | --- |
| `NotificationPath` | S3ToSQS \| S3ToSNSToSQS \| CloudTrailToSNSToSQS \| None | S3ToSQS | |
| `QueueMode` | CreateNew \| UseExisting | CreateNew | |
| `ExistingQueueArn` / `ExistingQueueUrl` | string | "" | Required for UseExisting |
| `QueueVisibilityTimeoutSeconds` | 0–43200 | 900 | |
| `MessageRetentionSeconds` | 60–1209600 | 345600 | |
| `DlqMaxReceiveCount` | 1–1000 | 5 | |
| `SubscriptionEmail` | email | "" | SNS ops alerts |

### 5. Encryption
| Parameter | Type / values | Default |
| --- | --- | --- |
| `BucketEncryption` | SSE-S3 \| SSE-KMS | SSE-S3 |
| `QueueEncryption` | SSE-SQS \| SSE-KMS | SSE-SQS |
| `KmsMode` | None \| CreateNew \| UseExisting | None |
| `ExistingKmsKeyArn` | KMS ARN | "" |

### 6. Bucket-policy hardening (advanced)
| Parameter | Type / values | Default | Notes |
| --- | --- | --- | --- |
| `RequireAclHeader` | auto \| true \| false | auto | `bucket-owner-full-control` on PutObject |
| `RestrictBySourceAccount` | true \| false | true | `aws:SourceAccount` |
| `SourceArnCondition` | string | "" | `aws:SourceArn` restriction |
| `LogDeliveryPrincipalOverride` | string | "" | Override service principal |

### 7. CloudTrail options
| Parameter | Values | Default |
| --- | --- | --- |
| `CtIsMultiRegion` | true/false | true |
| `CtIncludeGlobalServiceEvents` | true/false | true | *Forced to true when multi-region (AWS requirement)* |
| `CtIsOrganizationTrail` | true/false | false |
| `CtOrganizationId` | o-xxxx | "" |
| `CtIncludeManagementEvents` | true/false | true |
| `CtManagementReadWriteType` | All \| ReadOnly \| WriteOnly | All |
| `CtIncludeS3DataEvents` | true/false | false |
| `CtIncludeLambdaDataEvents` | true/false | false |
| `CtEnableInsights` | true/false | false |
| `CtEnableLogFileValidation` | true/false | true |

### 8. VPC Flow Logs options
| Parameter | Values | Default |
| --- | --- | --- |
| `VpcFlowResourceType` | VPC \| Subnet \| NetworkInterface | VPC |
| `VpcFlowResourceId` | id | "" |
| `VpcFlowTrafficType` | ALL \| ACCEPT \| REJECT | ALL |
| `VpcFlowMaxAggregationInterval` | 60 \| 600 | 600 |
| `VpcFlowLogFormat` | string | "" |

### 9. WAF / Route 53 options
| Parameter | Type | Default |
| --- | --- | --- |
| `WafWebAclArn` | ARN | "" |
| `Route53VpcIds` | comma list | "" |

### 10. Observability (optional; requires QueueMode=CreateNew)
| Parameter | Values | Default | Notes |
| --- | --- | --- | --- |
| `EnableDlqAlarm` | true/false | false | Alarm when DLQ has messages |
| `DlqAlarmThreshold` | >=1 | 1 | DLQ message count that fires |
| `EnableQueueAgeAlarm` | true/false | false | Alarm on oldest-message age |
| `QueueAgeAlarmSeconds` | >=60 | 3600 | Age threshold |
| `EnableDashboard` | true/false | false | CloudWatch dashboard |
| `AlarmEmail` | email | "" | Subscribed to the alarm topic |

---

## `aws-source-cloudwatch-logs-api`
| Parameter | Values | Default | Notes |
| --- | --- | --- | --- |
| `NamePrefix` | string | abstract-cwl | |
| `AuthMode` | AssumeRole \| AccessKey | AssumeRole | |
| `AbstractPrincipalArn` / `ExternalId` | — | "" | Required for AssumeRole |
| `MaxSessionDurationSeconds` | 900–43200 | 3600 | |
| `PermissionsBoundaryArn` | ARN | "" | |
| `StoreCredentialsInSecretsManager` | true/false | false | |
| `ExportToSsm` | true/false | false | |
| `LogGroupName` | string | "" | Scope target |
| `ScopeToSingleGroup` | true/false | false | Restrict to one group |
| `KmsKeyArn` | ARN | "" | For encrypted groups |

Grants `logs:DescribeLogGroups/DescribeLogStreams` (account-wide) and
`logs:GetLogEvents/FilterLogEvents/GetLogRecord/StartQuery/StopQuery/GetQueryResults`
(scoped to the group when `ScopeToSingleGroup=true`).

## `aws-source-kinesis-stream`
| Parameter | Values | Default | Notes |
| --- | --- | --- | --- |
| `NamePrefix` | string | abstract-kinesis | |
| `AuthMode` | AssumeRole \| AccessKey | AssumeRole | |
| `AbstractPrincipalArn` / `ExternalId` | — | "" | Required for AssumeRole |
| `StoreCredentialsInSecretsManager` / `ExportToSsm` | true/false | false | |
| `StreamMode` | CreateNew \| UseExisting | UseExisting | |
| `StreamName` | string | "" | Required |
| `ShardCount` | 1–1000 | 1 | New stream only |
| `ScopeToSingleStream` | true/false | true | |
| `KmsKeyArn` | ARN | "" | Encrypted stream |

Grants `kinesis:ListStreams/ListShards` plus
`Describe*/GetRecords/GetShardIterator/SubscribeToShard` (scoped to the stream when
`ScopeToSingleStream=true`).

## `aws-source-security-lake`
| Parameter | Values | Default | Notes |
| --- | --- | --- | --- |
| `SubscriberName` | string | abstract-security | |
| `AbstractAccountId` | 12-digit | "" | Subscriber principal |
| `ExternalId` | string (NoEcho) | "" | Required |
| `DataLakeArn` | ARN | "" | `aws securitylake list-data-lakes` |
| `SourceName` | WAFV2 \| ROUTE53 \| VPC_FLOW \| CLOUD_TRAIL_MGMT \| SH_FINDINGS \| LAMBDA_EXECUTION \| EKS_AUDIT \| S3_DATA \| ROUTE53_RESOLVER | WAFV2 | |
| `SourceVersion` | x.y | 2.0 | |
| `AccessType` | S3 \| LAKEFORMATION | S3 | |

## `aws-access-read-role-existing-bucket-and-queue` (role-only)
For an existing bucket + queue: `NamePrefix`, `AbstractPrincipalArn`, `ExternalId`,
`LogBucketName`, `LogBucketPrefix`, `SqsQueueArn`, `KmsKeyArn`, `PermissionsBoundaryArn`,
`MaxSessionDurationSeconds`, `CreateAccessKeyUser`.

## `aws-foundation-log-delivery-helper` (Lambda lookup / resolve / wiring)
| Parameter | Values | Default | Notes |
| --- | --- | --- | --- |
| `Operation` | None \| ResolveKmsKey \| ResolveQueue \| ValidateBucket \| ResolveStream \| ResolveWebAcl \| CheckLogGroup \| EnableS3SourceLogging \| EnableAlbAccessLogs | None | What the helper does |
| `AllowProducerWiring` | true/false | false | Attach write perms (auto-on for Enable* ops) |
| `KmsAlias` / `QueueName` / `BucketName` / `StreamName` / `WebAclName` / `WebAclScope` / `LogGroupName` | string | "" | Lookup inputs |
| `SourceBucketName` / `TargetBucketName` / `TargetPrefix` / `LoadBalancerArn` | string | "" | Producer-wiring inputs |
| `LogRetentionDays` | enum | 30 | Function log retention |
| `FunctionTimeout` | 10–300 | 60 | Lambda timeout |

Outputs by operation: `KmsKeyArn`, `QueueUrl`+`QueueArn`, `ValidatedBucket`, `StreamArn`,
`WebAclArn`; always exports `ServiceToken` for reuse from other stacks.

## `aws-source-multiple-sources-one-bucket` (nested)
Shared: `TemplateBaseUrl`, `AuthMode`, `AbstractPrincipalArn`, `ExternalId`,
`StoreCredentialsInSecretsManager`, `ExportToSsm`, `BucketEncryption`, `QueueEncryption`,
`KmsMode`, `ExistingKmsKeyArn`. Toggles: `EnableCloudTrail`, `EnableCloudFront`,
`EnableLoadBalancer`, `EnableRoute53`, `EnableS3AccessLogs`, `EnableVPCFlowLogs`, `EnableWAF`,
`EnableCloudWatchLogs`, `EnableKinesis`, `EnableSecurityLake`. Shared observability:
`EnableDlqAlarm`, `EnableDashboard`, `AlarmEmail`. Source inputs: `VpcFlowResourceId`,
`WafWebAclArn`, `KinesisStreamName`, `SecurityLakeDataLakeArn`, `SecurityLakeSourceName`.

---

## Appendix: OCSF & partitions

- **OCSF / Security Lake.** When ingesting via Security Lake (`aws-source-security-lake`),
  objects are already normalized to the Open Cybersecurity Schema Framework (OCSF) in parquet
  under the Security Lake bucket; Abstract reads them via the subscriber's S3 access + SQS
  notification. The direct S3+SQS sources deliver each service's **native** log format (e.g.
  CloudTrail JSON, VPC flow text/parquet, WAF JSON) — Abstract normalizes on ingest.
- **GovCloud / China.** Templates use `${AWS::Partition}`/`${AWS::Region}` everywhere, so they
  render correct ARNs in `aws-us-gov` and `aws-cn`. Before relying on a partition, confirm the
  source service and the Abstract principal/External ID are available there, and that
  Security Lake / WAFv2 scopes you need exist in that partition.
