# Set up AWS

<!-- Generated from tools/guides/aws.yml by `python -m tools.templates generate`. Do not edit. -->

For each log source you end up with three things in your AWS account: somewhere the logs land, an SQS queue (or a stream) that announces each new file, and an IAM role only Abstract can assume, with an External ID (a secret Abstract makes for your tenant: the role admits Abstract only when Abstract presents it). Two people usually share the work. The Abstract admin starts the integration in Abstract and records two values; the cloud admin deploys one stack in AWS with them; the Abstract admin then copies the stack's outputs into the same integration.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up. The same questions are in the [onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws), which gives each plan a link you can share.

## Where are your logs today?

- **Already landing in an S3 bucket** → [What is in that bucket?](#what-is-in-that-bucket)
  Includes a CloudTrail trail you already have.
- **Not in S3 yet. I want to start collecting an AWS service's logs** → [How many AWS accounts?](#how-many-aws-accounts)
  CloudTrail, VPC Flow Logs, WAF, load balancer, CloudFront, Route 53 Resolver, S3 access logs, or anything you write to S3.
- **In CloudWatch Logs** → [What is in the log group, and how busy is it?](#what-is-in-the-log-group-and-how-busy-is-it)
- **In a Kinesis data stream** → [Let Abstract read a Kinesis data stream](#let-abstract-read-a-kinesis-data-stream)
- **In Amazon Security Lake (WAF records)** → [Make Abstract a Security Lake subscriber for WAF records](#make-abstract-a-security-lake-subscriber-for-waf-records)
  Abstract's Security Lake integration reads WAF records. For other services in Security Lake, choose the service's own path.
- **In an AWS security service's own console** → [Which security service?](#which-security-service)
  GuardDuty findings, Security Hub findings, Network Firewall logs or AWS Config history that no bucket of yours receives yet.

## What is in the log group, and how busy is it?

- **Any log group at modest volume** → [Let Abstract read CloudWatch Logs directly](#let-abstract-read-cloudwatch-logs-directly)
- **EKS control-plane logs from a busy cluster** → [Send EKS control-plane logs from a busy cluster, through Firehose](#send-eks-control-plane-logs-from-a-busy-cluster-through-firehose)
  Audit logging on a busy cluster outruns an API read; Firehose takes the whole stream.

## Which security service?

- **GuardDuty findings** → [Send GuardDuty findings, through an encrypted bucket](#send-guardduty-findings-through-an-encrypted-bucket)
- **Security Hub findings** → [Send Security Hub findings, through EventBridge and Firehose](#send-security-hub-findings-through-eventbridge-and-firehose)
- **Network Firewall alert, flow or TLS logs** → [Send AWS Network Firewall logs, one queue per log type](#send-aws-network-firewall-logs-one-queue-per-log-type)
- **AWS Config configuration history** → [Send AWS Config configuration history, through a new bucket](#send-aws-config-configuration-history-through-a-new-bucket)

## What is in that bucket?

- **One source, and the bucket already notifies an SQS queue** → [Let Abstract read logs you already collect, with a read-only role](#let-abstract-read-logs-you-already-collect-with-a-read-only-role)
- **No queue yet, for one source or for several under different prefixes** → [Who owns the bucket's event notifications, and does anything else read them?](#who-owns-the-buckets-event-notifications-and-does-anything-else-read-them)
  Each source gets its own queue, because each needs its own integration and parser in Abstract. One source with no queue is a list of one.

## Who owns the bucket's event notifications, and does anything else read them?

S3 sends each event to only one place per prefix, and replacing a bucket's notification settings removes everyone else's.

- **My team owns them, and only Abstract needs the events** → [One queue per source, for a bucket you already have](#one-queue-per-source-for-a-bucket-you-already-have)
- **Other systems also need the same events** → [One queue per source, for a bucket other systems also read](#one-queue-per-source-for-a-bucket-other-systems-also-read)
- **Another team owns them, or the list of sources keeps growing** → [One queue per source, routed by EventBridge](#one-queue-per-source-routed-by-eventbridge)

## How many AWS accounts?

- **One account** → [Which source?](#which-source)
- **A few named accounts** → [Which source?](#which-source)
  Follow the plan once in each account. Each account gets its own stack and its own integration in Abstract, with its own External ID.
- **Every account in the organization** → [Which source, across the whole organization?](#which-source-across-the-whole-organization)
- **Every account in one organizational unit** → [Start collecting one source in every account of an organizational unit](#start-collecting-one-source-in-every-account-of-an-organizational-unit)
  A StackSet deploys the same source into every account of the unit, including accounts added to it later.

## Which source, across the whole organization?

- **CloudTrail** → [Send CloudTrail from every account in your organization](#send-cloudtrail-from-every-account-in-your-organization)
  One organization trail covers every account in the organization, including ones added later. It cannot be limited to one organizational unit.
- **Another source, in every account** → [Start collecting one source in every account of an organizational unit](#start-collecting-one-source-in-every-account-of-an-organizational-unit)

## Which source?

Several sources in the same account and Region? Choose the last answer.

- **CloudTrail (API activity)** → [Send CloudTrail from one account, with a new trail, bucket and queue](#send-cloudtrail-from-one-account-with-a-new-trail-bucket-and-queue)
- **VPC Flow Logs** → [Send VPC Flow Logs from one VPC, subnet or network interface](#send-vpc-flow-logs-from-one-vpc-subnet-or-network-interface)
- **WAF web ACL logs** → [Send WAF logs from one web ACL](#send-waf-logs-from-one-web-acl)
- **Load balancer access logs (Application, Network or Classic)** → [Send load balancer access logs](#send-load-balancer-access-logs)
- **CloudFront access logs** → [Send CloudFront access logs](#send-cloudfront-access-logs)
- **Route 53 Resolver DNS query logs** → [Send Route 53 Resolver DNS query logs from up to ten VPCs](#send-route-53-resolver-dns-query-logs-from-up-to-ten-vpcs)
- **S3 server access logs** → [Send S3 server access logs](#send-s3-server-access-logs)
- **Logs your own application writes to S3** → [Send logs your own application writes to S3](#send-logs-your-own-application-writes-to-s3)
- **Several of these, in one deploy** → [Start collecting several AWS sources in one account, in one deploy](#start-collecting-several-aws-sources-in-one-account-in-one-deploy)

## Send CloudTrail from one account, with a new trail, bucket and queue

**Fits when:** The account has no trail yet, or none that delivers to a bucket Abstract can read.

**Why this way:** The stack creates the trail, its bucket and a queue. CloudTrail announces each new log file through SNS to the queue, which is CloudTrail's own way of notifying.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.0). To send someone this plan, share this link.

**Not chosen:** A second trail beside one you already have: it bills every management event a second time. Read the existing trail's bucket instead.

**Not chosen:** An organization trail: only from the management account, and it covers every account.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Check first.** Cloud admin, in AWS CloudShell.

   Check that the account has no trail already, including an organization trail that Control Tower or AWS Organizations created.

   ```bash
   aws cloudtrail describe-trails --query 'trailList[].[Name,IsOrganizationTrail,S3BucketName,HomeRegion]' --output table
   ```

   **Check:** The table is empty. If it lists a trail, stop here: its logs already land in the bucket it names, so go back and answer Already landing in an S3 bucket.

3. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **CloudTrail via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

4. **Set up.** Cloud admin, in AWS console.

   Launch the CloudTrail stack with the two values from the shared record: Abstract's account ID in "Abstract principal ARN or 12-digit account ID" and the External ID in "External ID (shared secret from Abstract)". Leave everything else at its default.

   > **This changes:** Creates a new trail named abstract-trail in this account. The first copy of management events is free; if any other trail already delivers them, this one is billed for every event.

   Template: [CloudTrail to Abstract: new trail, bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudtrail-s3-sqs)

   ```bash
   aws cloudtrail get-trail-status --name abstract-trail --query '[IsLogging,LatestDeliveryTime]'
   ```

   **Check:** The stack shows CREATE_COMPLETE, and the command prints true and a LatestDeliveryTime within the last 15 minutes.

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **CloudTrail via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

6. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack deletes the trail. If it was the account's only trail, API activity is no longer logged anywhere.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE, and aws cloudtrail describe-trails no longer lists abstract-trail.

## Send VPC Flow Logs from one VPC, subnet or network interface

**Fits when:** The VPC, subnet or interface has no flow log Abstract can read yet.

**Why this way:** The stack creates the bucket and queue and turns the flow log on, so the bucket notifies the queue directly and nothing else needs wiring.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.1). To send someone this plan, share this link.

**Not chosen:** SNS fan-out by default: only when another consumer also needs the new-file notifications (see the note).

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **VPC / Transit Gateway Flow via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the VPC Flow Logs stack with the two values from the shared record and the ID to log in "VPC, subnet or network interface ID to log (required)". One stack logs one VPC, subnet or interface; the stack will not start without it.

   > **This changes:** Adds a flow log to that VPC, subnet or interface. Flow logs it already has are left alone and keep billing.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [VPC Flow Logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-vpc-flow-logs-s3-sqs)

   ```bash
   aws ec2 describe-flow-logs --filter Name=resource-id,Values=<your-vpc-subnet-or-eni-id> --query 'FlowLogs[].[FlowLogStatus,LogDestination]' --output table
   ```

   **Check:** The stack shows CREATE_COMPLETE, and the command lists an ACTIVE flow log whose destination is the stack's bucket.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **VPC / Transit Gateway Flow via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Custom Log Format:** Leave blank unless you set Flow log record format on the stack; then paste the same string
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack deletes the flow log it created; the VPC, subnet or interface is no longer logged to this bucket.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send WAF logs from one web ACL

**Fits when:** A WAF web ACL has no logging yet, or logging you are ready to replace.

**Why this way:** The stack creates a bucket whose name WAF accepts, turns on the web ACL's logging to it, and has the bucket notify the queue.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.2). To send someone this plan, share this link.

**Not chosen:** Keeping the web ACL's current logging as well: a web ACL has one logging configuration.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS WAF via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console, in the web ACL's Region (us-east-1 for a CloudFront web ACL).

   First run the command to see what the web ACL logs to today. Then launch the WAF stack with the two values from the shared record, the web ACL's ARN in "WAF web ACL ARN to log (required)", and Name prefix for created resources set to aws: WAF accepts only a bucket whose name starts with aws-waf-logs-, and the stack refuses to start without the ARN.

   > **This changes:** Replaces the web ACL's logging configuration. If the first command shows it already logs to Firehose, CloudWatch Logs or another bucket, that stops; deleting the stack later turns the web ACL's logging off.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [WAF logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-waf-logs-s3-sqs)

   Set: `NamePrefix` = `aws`

   ```bash
   aws wafv2 get-logging-configuration --resource-arn <web-acl-arn>
   aws wafv2 get-logging-configuration --resource-arn <web-acl-arn> --query LoggingConfiguration.LogDestinationConfigs
   ```

   **Check:** The stack shows CREATE_COMPLETE, and the second command prints only the stack's bucket ARN.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS WAF via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack turns the web ACL's logging off.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send load balancer access logs

**Fits when:** Application, Network or Classic Load Balancers in one account and Region should send access logs to Abstract.

**Why this way:** The stack creates the bucket the load balancers write to and the queue it notifies. AWS turns access logs on per load balancer, so you point each one at the bucket after the deploy.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.3). To send someone this plan, share this link.

**Not chosen:** A bucket in another Region: load balancers write access logs only to a bucket in their own Region.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS Load Balancer via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console, in the load balancers' Region.

   Launch the load balancer stack with the two values from the shared record.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [Load balancer logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-load-balancer-logs-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE and its Outputs tab lists BucketNameOut, SqsQueueUrl, SqsQueueArn and RoleArn.

4. **Set up.** Cloud admin, in AWS CloudShell.

   Turn on access logs on each load balancer, pointing at the bucket from the BucketNameOut output. The first command lists your load balancers. Use the second for Application and Network Load Balancers (a Network Load Balancer writes access logs only for TLS listeners) and the third for a Classic Load Balancer. In the console it is EC2, Load Balancers, the load balancer, Attributes, Edit, Access logs.

   > **This changes:** Changes each load balancer's access-log setting. A load balancer has one access-log bucket, so one that logs somewhere else today stops logging there.

   ```bash
   aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,Type,LoadBalancerArn]' --output table
   aws elbv2 modify-load-balancer-attributes --load-balancer-arn <load-balancer-arn> --attributes Key=access_logs.s3.enabled,Value=true Key=access_logs.s3.bucket,Value=<BucketNameOut>
   aws elb modify-load-balancer-attributes --load-balancer-name <classic-load-balancer-name> --load-balancer-attributes '{"AccessLog":{"Enabled":true,"S3BucketName":"<BucketNameOut>","EmitInterval":5}}'
   aws elbv2 describe-load-balancer-attributes --load-balancer-arn <load-balancer-arn> --query "Attributes[?starts_with(Key,'access_logs.s3')]"
   ```

   **Check:** The last command shows access_logs.s3.enabled true and the bucket, and within about 5 minutes of traffic the stack's bucket holds .log.gz files (S3 console, the bucket, Objects).

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS Load Balancer via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

6. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Turn access logs off on each load balancer (the same command with Value=false), because a load balancer whose bucket is gone keeps trying to write. Then delete the CloudFormation stack. The log bucket is kept on purpose: empty it in the S3 console, then delete it.

   > **This changes:** Turning access logs off on a load balancer stops its access logging everywhere, not only for Abstract.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send CloudFront access logs

**Fits when:** CloudFront distributions should send standard access logs to Abstract.

**Why this way:** The stack creates the bucket CloudFront's standard logging (v2) writes to and the queue it notifies. CloudFront turns logging on per distribution, so you point each one at the bucket after the deploy.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.4). To send someone this plan, share this link.

**Not chosen:** Legacy standard logging: it needs bucket ACLs, which the stack's bucket has switched off.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS CloudFront via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the CloudFront stack with the two values from the shared record.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [CloudFront logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudfront-logs-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE and its Outputs tab lists BucketNameOut, SqsQueueUrl, SqsQueueArn and RoleArn.

4. **Set up.** Cloud admin, in CloudFront console, or AWS CloudShell in us-east-1.

   Point each distribution's standard logging at the bucket from the BucketNameOut output. In the console: CloudFront, the distribution, Logging tab, Add, Amazon S3, the bucket's ARN (arn:aws:s3::: followed by the bucket name), output format W3C, field delimiter tab, and the standard fields in their standard order: the integration reads the classic tab-separated CloudFront line, field by field. The commands do the same and set the delimiter and the fields explicitly; run the first once and the next two once per distribution. Standard logging needs the Pro plan or pay-as-you-go pricing.

   > **This changes:** Adds a log delivery to each distribution. CloudFront bills standard-log delivery per GB; logging the distribution already has elsewhere is left alone.

   ```bash
   aws logs put-delivery-destination --region us-east-1 --name abstract-cloudfront --output-format w3c --delivery-destination-configuration destinationResourceArn=arn:aws:s3:::<BucketNameOut>
   aws logs put-delivery-source --region us-east-1 --name abstract-cf-<distribution-id> --resource-arn arn:aws:cloudfront::<account-id>:distribution/<distribution-id> --log-type ACCESS_LOGS
   aws logs create-delivery --region us-east-1 --delivery-source-name abstract-cf-<distribution-id> --delivery-destination-arn <deliveryDestination.arn printed by the first command> --field-delimiter $'\t' --record-fields date time x-edge-location sc-bytes c-ip cs-method 'cs(Host)' cs-uri-stem sc-status 'cs(Referer)' 'cs(User-Agent)' cs-uri-query 'cs(Cookie)' x-edge-result-type x-edge-request-id x-host-header cs-protocol cs-bytes time-taken x-forwarded-for ssl-protocol ssl-cipher x-edge-response-result-type cs-protocol-version fle-status fle-encrypted-fields c-port time-to-first-byte x-edge-detailed-result-type sc-content-type sc-content-len sc-range-start sc-range-end
   aws logs describe-deliveries --region us-east-1 --query 'deliveries[].[deliverySourceName,deliveryDestinationArn]' --output table
   ```

   **Check:** describe-deliveries lists one delivery per distribution to the abstract-cloudfront destination, and within about 10 minutes of traffic the stack's bucket holds log files (S3 console, the bucket, Objects).

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS CloudFront via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

6. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Remove each distribution's delivery (CloudFront, the distribution, Logging tab, or aws logs delete-delivery in us-east-1 with the delivery's id from describe-deliveries). Then delete the CloudFormation stack. The log bucket is kept on purpose: empty it in the S3 console, then delete it.

   > **This changes:** Removing a delivery stops that distribution's standard logging to this bucket.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send Route 53 Resolver DNS query logs from up to ten VPCs

**Fits when:** The DNS queries made from up to ten VPCs in one account and Region should reach Abstract.

**Why this way:** The stack creates one query-logging configuration that writes to a new bucket, and associates each VPC you name with it.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.5). To send someone this plan, share this link.

**Not chosen:** More than ten VPCs in one stack: deploy a second stack with a different name prefix for the rest.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS Route 53 via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the Route 53 Resolver stack with the two values from the shared record and the VPC IDs, comma-separated, in "VPC IDs whose DNS queries to log, up to 10 (required)". The stack logs the first ten and ignores any after that, and it will not start with none.

   > **This changes:** Starts logging every DNS query from those VPCs, billed per GB delivered. Query-logging configurations the VPCs already have are left alone.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [Route 53 DNS logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-route53-resolver-logs-s3-sqs)

   ```bash
   aws route53resolver list-resolver-query-log-config-associations --query 'ResolverQueryLogConfigAssociations[].[ResourceId,Status]' --output table
   ```

   **Check:** The stack shows CREATE_COMPLETE, and the command lists each VPC you named as ACTIVE.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS Route 53 via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack removes the query-logging configuration; DNS queries from those VPCs are no longer logged to this bucket.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send S3 server access logs

**Fits when:** Buckets in one account and Region should send server access logs to Abstract.

**Why this way:** The stack creates the bucket the access logs go to and the queue it notifies. S3 turns access logging on per source bucket, so you point each one at the new bucket after the deploy.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.6). To send someone this plan, share this link.

**Not chosen:** A log bucket in another Region or account: server access logs go to a bucket in the source bucket's own Region and account.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS S3 Access Logs via S3+SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the S3 access logs stack with the two values from the shared record.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [S3 access logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-s3-access-logs-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE and its Outputs tab lists BucketNameOut, SqsQueueUrl, SqsQueueArn and RoleArn.

4. **Set up.** Cloud admin, in AWS CloudShell.

   For each bucket whose access you want logged, first read its current setting, then point it at the bucket from the BucketNameOut output. Keep the target prefix under the stack's Log key prefix if you set one. In the console it is S3, the bucket, Properties, Server access logging, Edit.

   > **This changes:** A bucket has one access-log target. If the first command prints a TargetBucket, the second command replaces it and that bucket stops receiving this bucket's access logs.

   ```bash
   aws s3api get-bucket-logging --bucket <source-bucket>
   aws s3api put-bucket-logging --bucket <source-bucket> --bucket-logging-status '{"LoggingEnabled":{"TargetBucket":"<BucketNameOut>","TargetPrefix":"<source-bucket>/"}}'
   aws s3api get-bucket-logging --bucket <source-bucket>
   ```

   **Check:** The last command prints the new TargetBucket, and within about an hour of activity on the source bucket the stack's bucket holds log objects under the source bucket's name (S3 delivers these logs on a best-effort basis, often after a delay).

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS S3 Access Logs via S3+SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

6. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Turn access logging off on each source bucket, or point it back at the target you had (put-bucket-logging with --bucket-logging-status '{}' turns it off). Then delete the CloudFormation stack. The log bucket is kept on purpose: empty it in the S3 console, then delete it.

   > **This changes:** Turning access logging off on a source bucket stops its access logging everywhere, not only for Abstract.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send logs your own application writes to S3

**Fits when:** An application or tool of yours can write its logs to a bucket, one record format per bucket.

**Why this way:** The stack creates a bucket and a queue the bucket notifies; you point the writer at the bucket.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.7). To send someone this plan, share this link.

**Not chosen:** Several record formats in one bucket and queue: each format needs its own integration and parser.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the generic S3 stack with the two values from the shared record. Then give the writer s3:PutObject on the bucket from the BucketNameOut output and point it there.

   *Note:* If another consumer (another SIEM, a Lambda function, a data lake) also needs the new-file notifications, set Notification routing to S3ToSNSToSQS and subscribe it to the SnsTopicArn output.

   Template: [Any S3 logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-generic-s3-sqs)

   ```bash
   aws s3 ls s3://<BucketNameOut>/ --recursive | tail -5
   ```

   **Check:** The stack shows CREATE_COMPLETE, and once the writer has run, the command lists its files.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* Abstract has no ready-made parser for your application's records, so events arrive unparsed until your Abstract team adds one. If nothing arrives at all, a growing queue means the role ARN or External ID on the form does not match the stack.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn
   - **Data Format:** The writer's format: JSON, Newline Delimited (one JSON record per line), Apache Parquet or Concatenated JSON
   - **JSON Key:** Only when each file is one JSON object holding the records in one array; the name of that key

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Start collecting several AWS sources in one account, in one deploy

**Fits when:** You want several sources in the same account and Region, with the identity and encryption set once.

**Why this way:** One master stack nests the per-source stacks, so every source gets its own bucket, queue and role from a single launch.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.8). To send someone this plan, share this link.

**Not chosen:** One stack per source: more launches for the same result.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration for the first source you will switch on (the names are in the Verify step) and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates, into one record the cloud admin can read, such as a shared secrets vault entry. Every source shares this one External ID.

   *Note:* The form also asks for the bucket and the queue, which the deployment creates next, so you finish this form in the Verify step. Every integration on this deployment must be saved with this same External ID; the Verify step says what to do if a form will not keep it.

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the master stack with the two values from the shared record and switch on the sources you want. A source that needs an ID will not start without it: a VPC, subnet or interface ID for VPC Flow Logs, a web ACL ARN for WAF, and up to ten VPC IDs for Route 53 Resolver. Each source is its own nested stack with its own outputs, and each needs its own integration in Abstract. Every nested role trusts the one External ID the master stack was given, so each integration must be saved with that same External ID.

   > **This changes:** Turns on logging for the VPC Flow Logs, WAF and Route 53 sources you switch on; WAF replaces the web ACL's logging configuration. Load balancer, CloudFront and S3 access logs are not switched on by the stack: follow the second Set up step of that source's own plan, pointing at its nested stack's bucket.

   *Note:* If the integration form shows a new External ID and will not take yours, the extra integrations cannot assume their roles. Deploy one per-source stack per integration instead.

   Template: [Several AWS sources to Abstract in one deploy](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-multiple-sources-one-bucket)

   **Check:** The master and every nested stack show CREATE_COMPLETE.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Add one integration per source, each named for its source: CloudTrail via S3 + SQS, VPC / Transit Gateway Flow via S3 + SQS, AWS WAF via S3 + SQS, AWS Load Balancer via S3 + SQS, AWS CloudFront via S3 + SQS, AWS Route 53 via S3 + SQS, AWS S3 Access Logs via S3+SQS, GuardDuty via S3 + SQS, and AWS S3 SQS Source for anything else. In each, choose Role Based Authentication and fill SQS URL, AWS Region, S3 Bucket, AWS SQS Queue ARN, External ID and Assume Role ARN from that source's own outputs. Never point two integrations at the same queue: SQS gives each message to one reader, so each would get a random part of the logs, with no error. If a form shows a different External ID than the shared record and will not keep the shared value: while no integration on this deployment is saved yet, the cloud admin may change the deployment's External ID to the form's value; once any integration is saved, never change it, because every saved integration keeps presenting the old value and would stop. Deploy that source as its own stack, with its own External ID, instead.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   **Check:** For every source: within 15 minutes of a new log file landing, its queue's ApproximateNumberOfMessagesVisible goes back to 0, its dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for that integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the master stack deletes every nested stack and turns off the logging they turned on, including the WAF web ACL's.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send CloudTrail from every account in your organization

**Fits when:** You use AWS Organizations, have no organization trail yet, and want API activity from every account, including accounts added later.

**Why this way:** One organization trail, deployed once in the management account, already covers every member account. Abstract reads one bucket.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.2.0). To send someone this plan, share this link.

**Not chosen:** A StackSet with one trail per account: many trails and buckets for what one organization trail does.

**Not chosen:** A second organization trail beside an existing one: read the existing trail's bucket with the read-only role instead.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Check first.** Cloud admin, in AWS CloudShell, in the management account.

   Check for an organization trail you already have. Control Tower and many landing zones create one.

   ```bash
   aws cloudtrail describe-trails --query "trailList[?IsOrganizationTrail].[Name,S3BucketName,HomeRegion]" --output table
   aws organizations describe-organization --query Organization.Id --output text
   ```

   **Check:** The first command prints an empty table, and the second prints your organization ID (o-...). If the table lists a trail, stop: go back and answer Already landing in an S3 bucket, because a second organization trail bills every management event again in every account.

3. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **CloudTrail via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

4. **Set up.** Cloud admin, in AWS console, in the management account.

   Launch the CloudTrail stack in the management account (or a delegated administrator account) with the two values from the shared record, Organization trail? set to true, and the organization ID from the first step in Organization ID (o-xxxx).

   > **This changes:** Creates an organization trail that logs every account in the organization, including accounts added later. Where an account already has its own trail, this is a second, billed copy of its management events.

   Template: [CloudTrail to Abstract: new trail, bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudtrail-s3-sqs)

   Set: `CtIsOrganizationTrail` = `true`

   ```bash
   aws cloudtrail get-trail-status --name abstract-trail --query '[IsLogging,LatestDeliveryTime]'
   aws s3 ls s3://<BucketNameOut>/AWSLogs/ --recursive | head
   ```

   **Check:** The stack shows CREATE_COMPLETE, the trail is logging, and within about 15 minutes the bucket holds log files under AWSLogs/, then your organization ID, then one folder per account, for more than one account.

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **CloudTrail via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

6. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack deletes the organization trail. If it is the organization's only trail, API activity stops being logged in every account.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Start collecting one source in every account of an organizational unit

**Fits when:** The same source should exist in every account of an organizational unit, including accounts added later, and its stack needs no ID that differs per account, such as load balancer, S3 access or CloudFront logs.

**Why this way:** A service-managed StackSet rolls the source's stack into each account and Region, and into accounts added to the unit later.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.2.1). To send someone this plan, share this link.

**Not chosen:** Deploying account by account: slow, and new accounts are missed.

**Not chosen:** VPC Flow Logs, WAF or Route 53 Resolver: each stack needs a VPC or web ACL ID, and those differ in every account. Follow that source's plan once per account instead.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration for the source you will roll out (the names are in the Verify step) and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates, into one record the cloud admin can read. Every account's role trusts this one External ID.

   *Note:* The form also asks for the bucket and the queue, which the deployment creates next, so you finish this form in the Verify step. Every integration on this deployment must be saved with this same External ID; the Verify step says what to do if a form will not keep it.

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell, in the management account.

   Set the two values from the shared record as environment variables in CloudShell, as the commands show, then run the StackSet's deploy.sh from the management account or a delegated StackSets administrator, naming the source template, the organizational unit and the Regions. Never write the External ID into parameters.example.json or any file in the folder: those files are tracked and published. Each account gets its own bucket, queue and role. For load balancer, CloudFront or S3 access logs, still point the producers in each account at that account's bucket, as the source's own plan shows.

   > **This changes:** Deploys a stack into every account of the unit, and into each account added to it later, until the StackSet is deleted.

   Template: [One AWS source in every account: organization StackSet](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-s3-sqs-organization-stackset)

   ```bash
   read -rs ABSTRACT_EXTERNAL_ID && export ABSTRACT_EXTERNAL_ID
   export ABSTRACT_PRINCIPAL=<abstract-account-id>
   ./deploy.sh aws-source-<source>-s3-sqs <ou-id> "<region> [<region> ...]" --dry-run
   ./deploy.sh aws-source-<source>-s3-sqs <ou-id> "<region> [<region> ...]"
   aws cloudformation list-stack-instances --stack-set-name abstract-<source>-s3-sqs --query 'Summaries[].[Account,Region,Status]' --output table
   ```

   **Check:** Every stack instance in the StackSet shows CURRENT.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Add one integration per account, each named for the source (for example AWS Load Balancer via S3 + SQS), with Role Based Authentication, the same External ID, and SQS URL, AWS Region, S3 Bucket, AWS SQS Queue ARN and Assume Role ARN from that account's stack outputs (CloudFormation in that account, the stack, Outputs). If a form shows a different External ID than the shared record and will not keep the shared value: while no integration on this deployment is saved yet, the cloud admin may change the StackSet's External ID (deploy.sh --update) to the form's value; once any integration is saved, never change it, because every saved integration keeps presenting the old value and would stop. Deploy that source as its own stack, with its own External ID, instead.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <DeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   **Check:** For every source: within 15 minutes of a new log file landing, its queue's ApproximateNumberOfMessagesVisible goes back to 0, its dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for that integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then CloudShell in the management account.

   Delete the integrations in Abstract first. Then remove the stack instances from every account, wait for that operation to finish, and delete the StackSet. The StackSet is named abstract- plus the source, for example abstract-load-balancer-logs-s3-sqs. Each account's log bucket is kept; empty and delete it there if you no longer need the logs.

   ```bash
   aws cloudformation delete-stack-instances --stack-set-name abstract-<source>-s3-sqs --deployment-targets OrganizationalUnitIds=<ou-id> --regions <region> --no-retain-stacks
   aws cloudformation list-stack-set-operations --stack-set-name abstract-<source>-s3-sqs --max-results 1
   aws cloudformation delete-stack-set --stack-set-name abstract-<source>-s3-sqs
   ```

   **Check:** The last operation shows SUCCEEDED, and the StackSet no longer appears in list-stack-sets.

## Let Abstract read logs you already collect, with a read-only role

**Fits when:** The logs already land in a bucket that notifies an SQS queue, and only Abstract will read that queue.

**Why this way:** Nothing about your bucket or queue changes. The stack creates only the role Abstract assumes.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.0). To send someone this plan, share this link.

**Not chosen:** A new bucket and queue: you already have both.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named for what the bucket holds (the names are in the Verify step) and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates, into one record the cloud admin can read, such as a shared secrets vault entry.

   *Note:* Your bucket and queue already exist, so you can fill SQS URL, S3 Bucket and AWS SQS Queue ARN now. Only Assume Role ARN waits for the stack, in the Verify step.

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the read role stack with the two values from the shared record, your bucket name and your queue's ARN.

   *Note:* Never point a second integration at the same queue. SQS hands each message to only one reader, so two readers would each get a random half, with no error.

   Template: [Existing S3 logs to Abstract: read-only access role](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-access-read-role-existing-bucket-and-queue)

   **Check:** The stack shows CREATE_COMPLETE and outputs RoleArn.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Finish the integration you started, the one named for what the bucket holds: CloudTrail via S3 + SQS, VPC / Transit Gateway Flow via S3 + SQS, AWS WAF via S3 + SQS, AWS Load Balancer via S3 + SQS, AWS CloudFront via S3 + SQS, AWS Route 53 via S3 + SQS, AWS S3 Access Logs via S3+SQS, GuardDuty via S3 + SQS, or AWS S3 SQS Source for anything else. Fill SQS URL and AWS SQS Queue ARN with your queue's, S3 Bucket with your bucket, AWS Region with theirs, External ID with the value in the shared record, and Assume Role ARN with the stack's RoleArn output. If the form shows a different External ID, the cloud admin changes the stack's External ID to match (Update, Use existing template) before you save.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <your-queue-url> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   **Check:** Within 15 minutes of a new log file landing, your queue's ApproximateNumberOfMessagesVisible goes back to 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack removes only Abstract's role. Your bucket, queue and logs are untouched.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## One queue per source, for a bucket you already have

**Fits when:** A bucket you own holds one source, or several under different prefixes, with no queue yet, and only Abstract needs the events.

**Why this way:** Each prefix notifies its own queue directly, so each source gets its own integration and parser in Abstract.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.1.0). To send someone this plan, share this link.

**Not chosen:** SNS or EventBridge: nothing else needs the events.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration for the first source in the bucket (the names are in the Verify step) and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates, into one record the cloud admin can read. Every source's queue is read by one role that trusts this External ID.

   *Note:* The form also asks for the bucket and the queue, which the deployment creates next, so you finish this form in the Verify step. Every integration on this deployment must be saved with this same External ID; the Verify step says what to do if a form will not keep it.

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell, with Terraform.

   Deploy the shared-bucket template with routing_mode = direct, manage_bucket_notification = false (the default), the two values from the shared record as TF_VAR_abstract_aws_account_id and TF_VAR_external_id environment variables (never in terraform.tfvars or any other file), and each source's prefix. Terraform creates the queues and the role and does not touch the bucket.

   Template: [Shared S3 bucket to Abstract: one queue per source](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-existing-bucket-queues)

   Set: `routing_mode` = `direct`, `manage_bucket_notification` = `False`

   ```bash
   terraform apply
   terraform output abstract_configurations
   ```

   **Check:** terraform apply completes, and abstract_configurations lists one queue per source.

4. **Set up.** Bucket owner, in AWS CloudShell, in the Terraform folder.

   Save the bucket's current notification configuration first: it is your rollback. Then add the queue entries from the bucket_notification_plan output to it, keeping every entry already there, write the result back, and compare. The commands do exactly that; put the bucket's name where they say bucket.

   > **This changes:** Rewrites the bucket's notification configuration. A bucket has one, and every write replaces all of it, so writing anything but the merged file removes other teams' notifications. If two teams edit it at once, one loses: agree a time.

   ```bash
   aws s3api get-bucket-notification-configuration --bucket <bucket> > notification-backup.json
   [ -s notification-backup.json ] || echo '{}' > notification-backup.json
   terraform output -raw bucket_notification_plan > plan.json
   jq -s '(.[0] | del(.ResponseMetadata)) as $cur | .[1] as $add | $cur + {QueueConfigurations: (($cur.QueueConfigurations // []) + ($add.QueueConfigurations // [])), TopicConfigurations: (($cur.TopicConfigurations // []) + ($add.TopicConfigurations // []))}' notification-backup.json plan.json > merged.json
   aws s3api put-bucket-notification-configuration --bucket <bucket> --notification-configuration file://merged.json
   aws s3api get-bucket-notification-configuration --bucket <bucket> | jq -r '[.[]? | arrays | .[].Id] | sort | .[]'
   ```

   **Check:** The last command lists every Id that was in notification-backup.json plus one abstract- Id per source (or abstract-fanout). If an old Id is missing, put notification-backup.json back with put-bucket-notification-configuration. S3 refuses a write whose prefix and suffix overlap an existing entry's; the error names it.

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Add one integration per entry in the abstract_configurations output, the one named for that source: CloudTrail via S3 + SQS, VPC / Transit Gateway Flow via S3 + SQS, AWS WAF via S3 + SQS, AWS Load Balancer via S3 + SQS, AWS CloudFront via S3 + SQS, AWS Route 53 via S3 + SQS, AWS S3 Access Logs via S3+SQS, GuardDuty via S3 + SQS, or AWS S3 SQS Source for anything else. Choose Role Based Authentication and fill SQS URL (sqs_url), AWS Region (region), S3 Bucket (s3_bucket), AWS SQS Queue ARN (sqs_queue_arn), External ID (the shared record, also the external_id output) and Assume Role ARN (role_arn); for AWS S3 SQS Source also Data Format (dataformat). If a form shows a different External ID than the shared record and will not keep the shared value: while no integration is saved yet, the cloud admin may set TF_VAR_external_id to the form's value and run terraform apply again; once any integration is saved, never change it, because every saved integration keeps presenting the old value and would stop. Give that source its own deployment instead.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   terraform output verification_commands
   ```

   **Check:** For every source: within 15 minutes of a new log file landing, its queue's ApproximateNumberOfMessagesVisible goes back to 0, its dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for that integration's events returns results.

6. **Clean up.** Cloud admin, Abstract admin and the bucket owner, in Abstract console, then CloudShell with Terraform.

   Delete the integrations in Abstract first, so they stop polling. Then the bucket owner removes the abstract- entries from the bucket's notifications, keeping everyone else's (with EventBridge routing, also switch EventBridge off with del(.EventBridgeConfiguration) if nothing else uses it). Then destroy, in the same folder and with the same state. Your bucket and its logs are never touched.

   > **This changes:** Rewrites the bucket's notification configuration once more. Save it first, as the commands do.

   ```bash
   aws s3api get-bucket-notification-configuration --bucket <bucket> > before-cleanup.json
   jq 'del(.ResponseMetadata) | with_entries(if (.value | type) == "array" then .value |= map(select((.Id // "") | startswith("abstract-") | not)) else . end)' before-cleanup.json > cleaned.json
   aws s3api put-bucket-notification-configuration --bucket <bucket> --notification-configuration file://cleaned.json
   terraform destroy
   ```

   **Check:** terraform destroy completes, and the bucket's notification configuration no longer names an Abstract queue or topic.

## One queue per source, for a bucket other systems also read

**Fits when:** One bucket holds one source or several, other systems need the same events, and every new-object notification the bucket has can move onto one SNS topic.

**Why this way:** The bucket notifies one SNS topic, and each source's queue subscribes with a filter, so the other systems can subscribe too.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.1.1). To send someone this plan, share this link.

**Not chosen:** Direct notifications: they would take the events away from the other systems.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration for the first source in the bucket (the names are in the Verify step) and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates, into one record the cloud admin can read. Every source's queue is read by one role that trusts this External ID.

   *Note:* The form also asks for the bucket and the queue, which the deployment creates next, so you finish this form in the Verify step. Every integration on this deployment must be saved with this same External ID; the Verify step says what to do if a form will not keep it.

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell, with Terraform.

   Deploy the shared-bucket template with routing_mode = sns, manage_bucket_notification = false (the default), the two values from the shared record as TF_VAR_abstract_aws_account_id and TF_VAR_external_id environment variables (never in terraform.tfvars or any other file), and each source's prefix. Terraform creates the topic, the queues and the role and does not touch the bucket.

   Template: [Shared S3 bucket to Abstract: one queue per source](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-existing-bucket-queues)

   Set: `routing_mode` = `sns`, `manage_bucket_notification` = `False`

   ```bash
   terraform apply
   terraform output sns_topic_arn
   ```

   **Check:** terraform apply completes, and each source's queue is subscribed to the topic.

4. **Set up.** Bucket owner, in AWS CloudShell, in the Terraform folder.

   Save the bucket's current notification configuration first: it is your rollback. The topic entry has no prefix filter, so it overlaps every other new-object notification on the bucket, for any prefix, and S3 refuses the write while one exists. The third command counts them: it must print 0. If it does not, move each of those consumers onto the topic first (subscribe it with a filter for its own prefix, then remove its bucket entry), or use EventBridge routing instead. Then add the topic entry and compare.

   > **This changes:** Rewrites the bucket's notification configuration. A bucket has one, and every write replaces all of it, so writing anything but the merged file removes other teams' notifications.

   ```bash
   aws s3api get-bucket-notification-configuration --bucket <bucket> > notification-backup.json
   [ -s notification-backup.json ] || echo '{}' > notification-backup.json
   jq '[(.QueueConfigurations, .TopicConfigurations, .LambdaFunctionConfigurations)[]? | select(any(.Events[]; startswith("s3:ObjectCreated")))] | length' notification-backup.json
   terraform output -raw bucket_notification_plan > plan.json
   jq -s '(.[0] | del(.ResponseMetadata)) as $cur | .[1] as $add | $cur + {TopicConfigurations: (($cur.TopicConfigurations // []) + ($add.TopicConfigurations // []))}' notification-backup.json plan.json > merged.json
   aws s3api put-bucket-notification-configuration --bucket <bucket> --notification-configuration file://merged.json
   aws s3api get-bucket-notification-configuration --bucket <bucket> | jq -r '[.[]? | arrays | .[].Id] | sort | .[]'
   ```

   **Check:** The last command lists every Id that was in notification-backup.json plus abstract-fanout. If an old Id is missing, put notification-backup.json back with put-bucket-notification-configuration.

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Add one integration per entry in the abstract_configurations output, the one named for that source: CloudTrail via S3 + SQS, VPC / Transit Gateway Flow via S3 + SQS, AWS WAF via S3 + SQS, AWS Load Balancer via S3 + SQS, AWS CloudFront via S3 + SQS, AWS Route 53 via S3 + SQS, AWS S3 Access Logs via S3+SQS, GuardDuty via S3 + SQS, or AWS S3 SQS Source for anything else. Choose Role Based Authentication and fill SQS URL (sqs_url), AWS Region (region), S3 Bucket (s3_bucket), AWS SQS Queue ARN (sqs_queue_arn), External ID (the shared record, also the external_id output) and Assume Role ARN (role_arn); for AWS S3 SQS Source also Data Format (dataformat). If a form shows a different External ID than the shared record and will not keep the shared value: while no integration is saved yet, the cloud admin may set TF_VAR_external_id to the form's value and run terraform apply again; once any integration is saved, never change it, because every saved integration keeps presenting the old value and would stop. Give that source its own deployment instead.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   terraform output verification_commands
   ```

   **Check:** For every source: within 15 minutes of a new log file landing, its queue's ApproximateNumberOfMessagesVisible goes back to 0, its dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for that integration's events returns results.

6. **Clean up.** Cloud admin, Abstract admin and the bucket owner, in Abstract console, then CloudShell with Terraform.

   Delete the integrations in Abstract first, so they stop polling. Then the bucket owner removes the abstract- entries from the bucket's notifications, keeping everyone else's (with EventBridge routing, also switch EventBridge off with del(.EventBridgeConfiguration) if nothing else uses it). Then destroy, in the same folder and with the same state. Your bucket and its logs are never touched.

   > **This changes:** Rewrites the bucket's notification configuration once more. Save it first, as the commands do.

   ```bash
   aws s3api get-bucket-notification-configuration --bucket <bucket> > before-cleanup.json
   jq 'del(.ResponseMetadata) | with_entries(if (.value | type) == "array" then .value |= map(select((.Id // "") | startswith("abstract-") | not)) else . end)' before-cleanup.json > cleaned.json
   aws s3api put-bucket-notification-configuration --bucket <bucket> --notification-configuration file://cleaned.json
   terraform destroy
   ```

   **Check:** terraform destroy completes, and the bucket's notification configuration no longer names an Abstract queue or topic.

## One queue per source, routed by EventBridge

**Fits when:** Another team owns the bucket's notifications, or the list of sources keeps growing and needs richer filtering.

**Why this way:** EventBridge rules filter on more than prefix and suffix, and adding a source adds a rule instead of rewriting the bucket's settings.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.1.2). To send someone this plan, share this link.

**Not chosen:** Direct notifications: you cannot safely edit a bucket another team owns.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration for the first source in the bucket (the names are in the Verify step) and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates, into one record the cloud admin can read. Every source's queue is read by one role that trusts this External ID.

   *Note:* The form also asks for the bucket and the queue, which the deployment creates next, so you finish this form in the Verify step. Every integration on this deployment must be saved with this same External ID; the Verify step says what to do if a form will not keep it.

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell, with Terraform.

   Deploy the shared-bucket template with routing_mode = eventbridge, manage_bucket_notification = false (the default), the two values from the shared record as TF_VAR_abstract_aws_account_id and TF_VAR_external_id environment variables (never in terraform.tfvars or any other file), and each source's prefix. Terraform creates one rule and queue per source and the role, and does not touch the bucket.

   Template: [Shared S3 bucket to Abstract: one queue per source](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-existing-bucket-queues)

   Set: `routing_mode` = `eventbridge`, `manage_bucket_notification` = `False`

   ```bash
   terraform apply
   terraform output manual_bucket_steps
   ```

   **Check:** terraform apply completes, and eventbridge_rule_arns lists one rule per source.

4. **Set up.** Bucket owner, in AWS CloudShell.

   Save the bucket's notification configuration first: it is your rollback. Then run the manual_bucket_steps output, which switches EventBridge on for the bucket while keeping every existing notification. Switching it on with nothing else in the request removes them all.

   > **This changes:** Rewrites the bucket's notification configuration, and once EventBridge is on, S3 sends every event on this bucket to EventBridge in this account.

   ```bash
   aws s3api get-bucket-notification-configuration --bucket <bucket> > notification-backup.json
   terraform output manual_bucket_steps
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The last command shows "EventBridgeConfiguration": {} and every entry that was in notification-backup.json. If one is missing, put notification-backup.json back with put-bucket-notification-configuration.

5. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Add one integration per entry in the abstract_configurations output, the one named for that source: CloudTrail via S3 + SQS, VPC / Transit Gateway Flow via S3 + SQS, AWS WAF via S3 + SQS, AWS Load Balancer via S3 + SQS, AWS CloudFront via S3 + SQS, AWS Route 53 via S3 + SQS, AWS S3 Access Logs via S3+SQS, GuardDuty via S3 + SQS, or AWS S3 SQS Source for anything else. Choose Role Based Authentication and fill SQS URL (sqs_url), AWS Region (region), S3 Bucket (s3_bucket), AWS SQS Queue ARN (sqs_queue_arn), External ID (the shared record, also the external_id output) and Assume Role ARN (role_arn); for AWS S3 SQS Source also Data Format (dataformat). If a form shows a different External ID than the shared record and will not keep the shared value: while no integration is saved yet, the cloud admin may set TF_VAR_external_id to the form's value and run terraform apply again; once any integration is saved, never change it, because every saved integration keeps presenting the old value and would stop. Give that source its own deployment instead.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   terraform output verification_commands
   ```

   **Check:** For every source: within 15 minutes of a new log file landing, its queue's ApproximateNumberOfMessagesVisible goes back to 0, its dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for that integration's events returns results.

6. **Clean up.** Cloud admin, Abstract admin and the bucket owner, in Abstract console, then CloudShell with Terraform.

   Delete the integrations in Abstract first, so they stop polling. Then the bucket owner removes the abstract- entries from the bucket's notifications, keeping everyone else's (with EventBridge routing, also switch EventBridge off with del(.EventBridgeConfiguration) if nothing else uses it). Then destroy, in the same folder and with the same state. Your bucket and its logs are never touched.

   > **This changes:** Rewrites the bucket's notification configuration once more. Save it first, as the commands do.

   ```bash
   aws s3api get-bucket-notification-configuration --bucket <bucket> > before-cleanup.json
   jq 'del(.ResponseMetadata) | with_entries(if (.value | type) == "array" then .value |= map(select((.Id // "") | startswith("abstract-") | not)) else . end)' before-cleanup.json > cleaned.json
   aws s3api put-bucket-notification-configuration --bucket <bucket> --notification-configuration file://cleaned.json
   terraform destroy
   ```

   **Check:** terraform destroy completes, and the bucket's notification configuration no longer names an Abstract queue or topic.

## Let Abstract read CloudWatch Logs directly

**Fits when:** The logs are in CloudWatch Logs, at modest volume.

**Why this way:** Abstract reads the log groups by API. Nothing is copied to S3.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=2.0). To send someone this plan, share this link.

**Not chosen:** Exporting to S3 first: worth it only at high volume.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the log group, which you can fill now. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS CloudWatch Logs** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the CloudWatch Logs stack with the two values from the shared record, naming the log group Abstract may read.

   *Note:* The integration reads one log group, so add one integration per log group. For high-volume log groups, API reads cost more than a subscription to a stream. EKS control-plane logs have a Firehose template; other log groups do not yet.

   Template: [CloudWatch Logs to Abstract: direct API read](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudwatch-logs-api)

   **Check:** The stack shows CREATE_COMPLETE and outputs RoleArn and AwsRegion.

4. **Verify.** Abstract admin, in Abstract console.

   Finish the integration you started, as the table shows. Before you save, compare the External ID on the form with the one in the shared record; if they differ, the cloud admin updates the stack's External ID to the form's value (Update, Use existing template), and you save after UPDATE_COMPLETE.

   *Note:* If nothing arrives, check that the log group still receives events (CloudWatch, Log groups, the group, Log streams, newest first) and that Assume Role ARN and External ID match the stack.

   In Abstract, add the **AWS CloudWatch Logs** integration and fill in:

   - **Region:** AwsRegion
   - **Log Group Name:** The log group the stack lets Abstract read
   - **Log Stream Name Match Pattern:** .* (every stream) unless you want fewer
   - **Authentication Type:** Role Based Authentication
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of new events in the log group, a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Let Abstract read a Kinesis data stream

**Fits when:** Records already flow into a Kinesis data stream, or should.

**Why this way:** Abstract reads the stream directly; there is no bucket or queue.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=3). To send someone this plan, share this link.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the stream name and Region, which you can fill now if the stream exists. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS Kinesis Integration** and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console.

   Launch the Kinesis stack with the two values from the shared record. Choose your existing stream, or let it create one.

   Template: [Kinesis stream to Abstract: direct stream read](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-kinesis-stream)

   **Check:** The stack shows CREATE_COMPLETE and outputs StreamNameOut, StreamArn and RoleArn.

4. **Verify.** Abstract admin, in Abstract console.

   Finish the integration you started, as the table shows. Before you save, compare the External ID on the form with the one in the shared record; if they differ, the cloud admin updates the stack's External ID to the form's value (Update, Use existing template), and you save after UPDATE_COMPLETE.

   *Note:* If nothing arrives, check that records are still being written (Kinesis, the stream, Monitoring, Incoming data) and that Assume Role ARN and External ID match the stack.

   In Abstract, add the **AWS Kinesis Integration** and fill in:

   - **Stream Name:** StreamNameOut
   - **AWS Region:** AwsRegion
   - **Newline Delimited:** On only if each record holds several records, one per line
   - **Compression:** Gzip if the producer compresses records; otherwise None
   - **Authentication Type:** Role Based Authentication
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of new records, a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Make Abstract a Security Lake subscriber for WAF records

**Fits when:** Your WAF logs are centralised in Amazon Security Lake.

**Why this way:** Abstract subscribes to Security Lake and is notified of each new object, without a bucket of your own.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=4). To send someone this plan, share this link.

**Not chosen:** Other Security Lake sources: Abstract's Security Lake integration reads WAF records; use each service's own plan for the rest.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS WAF Security Lake via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in AWS console, in the Security Lake delegated administrator account.

   Launch the Security Lake stack with the External ID from the shared record. Give Abstract's account as the bare 12-digit account ID, not an ARN.

   > **This changes:** Gives Abstract's account read access to the Security Lake objects for the source you choose, through a resource share.

   Template: [Security Lake to Abstract: subscriber and SQS notification](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-security-lake)

   **Check:** In Security Lake, Subscribers, the subscriber shows as active, and the stack's Outputs tab lists SubscriberRoleArn and S3BucketArn.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs list-queues
   aws sqs get-queue-attributes --queue-url <subscriber-queue-url> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS WAF Security Lake via S3 + SQS** integration and fill in:

   - **SQS URL:** The queue Security Lake created for this subscriber (aws sqs list-queues)
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** The bucket name in S3BucketArn (the part after arn:aws:s3:::)
   - **AWS SQS Queue ARN:** The same queue's ARN
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** SubscriberRoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack removes Abstract's Security Lake subscription and its access to the objects.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send GuardDuty findings, through an encrypted bucket

**Fits when:** GuardDuty is on in this Region and its findings should reach Abstract.

**Why this way:** GuardDuty exports findings only to S3, and only under a customer managed KMS key. The stack creates the key, the bucket, the queue and the role, and points your detector's export at the bucket.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.0). To send someone this plan, share this link.

**Not chosen:** Security Hub: worth it only if you collect it anyway; a second path duplicates every finding.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **GuardDuty via S3 + SQS** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell, in the GuardDuty delegated administrator account for an organization.

   Run the GuardDuty template's deploy.sh with the two values from the shared record and your detector ID. If the detector already exports to another bucket, set CreatePublishingDestination to false and decide which export to keep. Then set the detector's finding-update frequency to 15 minutes, or updated findings lag the console by up to six hours.

   > **This changes:** Adds a publishing destination to your detector, and the frequency change applies to every export the detector has.

   Template: [GuardDuty findings to Abstract: new key, bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-guardduty-findings-s3-sqs)

   ```bash
   aws guardduty list-publishing-destinations --detector-id <detector-id>
   aws guardduty update-detector --detector-id <detector-id> --finding-publishing-frequency FIFTEEN_MINUTES
   ```

   **Check:** The stack shows CREATE_COMPLETE, and list-publishing-destinations shows the bucket as PUBLISHING.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* If nothing arrives: a queue whose count keeps growing means Abstract is not reading it, so check that Assume Role ARN and External ID on the form match the stack; messages in the dead-letter queue mean Abstract took them and could not read the file, usually a KMS key that does not admit the role.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <SqsDeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **GuardDuty via S3 + SQS** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the stack; that also removes the detector's export to the bucket. The bucket and the KMS key are kept on purpose, because the findings in the bucket are encrypted under that key: empty and delete the bucket first, and only then schedule the key for deletion.

   > **This changes:** Deleting the stack removes the detector's export to this bucket. Other exports are left alone.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE and list-publishing-destinations no longer lists the bucket.

## Send AWS Network Firewall logs, one queue per log type

**Fits when:** An AWS Network Firewall has no logging yet, and its alert (and flow or TLS) logs should reach Abstract.

**Why this way:** Alert, flow and TLS logs are three different record shapes. The stack logs each to its own prefix and notifies its own queue, so each gets its own integration and parser in Abstract.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.2). To send someone this plan, share this link.

**Not chosen:** One queue for all three types: mixed shapes in one integration parse badly.

**Not chosen:** A bucket you already log to: use the shared-bucket template's per-prefix queues instead.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the deployment creates next, so you finish this form in the Verify step. Every integration on this deployment must be saved with this same External ID; the Verify step says what to do if a form will not keep it.

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell.

   Run the Network Firewall template's deploy.sh with the two values from the shared record and your firewall's ARN. Alert logs are always on; choose flow and TLS logs. Later, switch one log type per stack update: Network Firewall accepts only one logging change at a time.

   > **This changes:** Sets the firewall's logging configuration. The firewall must have none today; the stack refuses one that does.

   Template: [Network Firewall logs to Abstract: bucket and three queues](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-network-firewall-logs-s3-sqs)

   ```bash
   aws network-firewall describe-logging-configuration --firewall-arn <firewall-arn>
   ```

   **Check:** The stack shows CREATE_COMPLETE, and the command lists the bucket for each type you chose.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Add one AWS S3 SQS Source integration per log type you turned on (the first one is the integration you started), each with that type's queue and the same External ID, as the table shows for alert logs; for flow and TLS logs use FlowQueueUrl and FlowQueueArn, or TlsQueueUrl and TlsQueueArn. All of them share one role. If a form shows a different External ID than the shared record and will not keep the shared value: while none of these integrations is saved yet, the cloud admin may change the stack's External ID to the form's value; once one is saved, never change it, because it keeps presenting the old value and would stop.

   *Note:* Abstract has no ready-made Network Firewall parser in this integration, so events arrive unparsed until your Abstract team adds one for each log type. If nothing arrives at all, a growing queue means the role ARN or External ID on the form does not match the stack.

   ```bash
   aws sqs get-queue-attributes --queue-url <AlertQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <AlertDeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **SQS URL:** AlertQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** AlertQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn
   - **Data Format:** Newline Delimited (one JSON record per line)

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integrations in Abstract first, so they stop polling. Then delete the stack. The log bucket is kept on purpose: empty it in the S3 console, then delete it.

   > **This changes:** Deleting the stack turns the firewall's logging off.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE and describe-logging-configuration shows no destinations.

## Send AWS Config configuration history, through a new bucket

**Fits when:** AWS Config records this Region and its configuration history should reach Abstract.

**Why this way:** AWS Config delivers history files only to S3. The stack creates a bucket AWS Config may write to and a queue notified for each history file; you point the account's delivery channel at it.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.3). To send someone this plan, share this link.

**Not chosen:** Reading the bucket AWS Config already uses: possible with the read-only role, but its notifications are usually owned by someone else.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell.

   Save the delivery channel exactly as it is today, every field: it is your rollback. Then run the AWS Config template's deploy.sh with the two values from the shared record. Leave CreateDeliveryChannel at false when the account already has a delivery channel (most do), and repoint that channel with the commands: they copy the saved channel, change only the bucket, and drop the key prefix and KMS key the new bucket cannot use, so the SNS topic and snapshot frequency carry over.

   > **This changes:** Repointing the delivery channel moves all future configuration history out of the bucket it uses today. Anything reading that bucket (an aggregator, a log archive, another SIEM) stops receiving files. In a Control Tower account, Control Tower manages the channel: change it there or not at all.

   Template: [AWS Config history to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-config-history-s3-sqs)

   ```bash
   aws configservice describe-delivery-channels > config-channel-backup.json
   jq '.DeliveryChannels[0] | .s3BucketName = "<BucketNameOut>" | del(.s3KeyPrefix, .s3KmsKeyArn)' config-channel-backup.json > config-channel-abstract.json
   aws configservice put-delivery-channel --delivery-channel file://config-channel-abstract.json
   aws configservice describe-delivery-channels --query 'DeliveryChannels[].[name,s3BucketName,s3KeyPrefix,snsTopicARN]' --output table
   ```

   **Check:** The stack shows CREATE_COMPLETE, config-channel-backup.json holds the old channel, and the last command shows the new bucket, no key prefix, and the same SNS topic as before.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* Abstract has no ready-made AWS Config parser, so events arrive unparsed until your Abstract team adds one. If nothing arrives at all, a growing queue means the role ARN or External ID on the form does not match the stack.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <SqsDeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn
   - **Data Format:** JSON
   - **JSON Key:** configurationItems

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. If you repointed an existing channel, restore it from config-channel-backup.json with the first two commands: that puts back every field, including the old key prefix, KMS key and SNS topic, not only the bucket. A channel the stack created is deleted with the stack, and AWS Config then delivers nothing. Then delete the stack. The bucket is kept on purpose: empty it, then delete it.

   > **This changes:** Deleting a delivery channel the stack created stops AWS Config history delivery for the account.

   ```bash
   jq '.DeliveryChannels[0]' config-channel-backup.json > config-channel-original.json
   aws configservice put-delivery-channel --delivery-channel file://config-channel-original.json
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   aws configservice describe-delivery-channels
   ```

   **Check:** The stack shows DELETE_COMPLETE, and the last command prints the same channel as config-channel-backup.json.

## Send Security Hub findings, through EventBridge and Firehose

**Fits when:** Security Hub (or Security Hub CSPM) is on and its findings should reach Abstract.

**Why this way:** Security Hub sends findings only to EventBridge. The stack routes them through Firehose into a bucket, one finding per line, and notifies a queue Abstract polls.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.1). To send someone this plan, share this link.

**Not chosen:** Security Lake: Abstract's Security Lake integration reads WAF records only.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell, in the Security Hub administrator account's aggregation Region.

   Run the Security Hub template's deploy.sh with the two values from the shared record. Choose the finding events: "Security Hub Findings - Imported" for Security Hub CSPM (ASFF, the older finding format), or "Findings Imported V2" for Security Hub (OCSF, the newer one). For both, deploy the stack twice with different name prefixes, one per format.

   Template: [Security Hub findings to Abstract: EventBridge and Firehose](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-security-hub-findings-firehose)

   ```bash
   aws s3 ls s3://<BucketNameOut>/securityhub/ --recursive | tail -5
   ```

   **Check:** The stack shows CREATE_COMPLETE, and after the next finding update the command lists objects under securityhub/.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* Abstract has no ready-made Security Hub parser, so events arrive unparsed until your Abstract team adds one for the format you chose. If nothing arrives at all, a growing queue means the role ARN or External ID on the form does not match the stack.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <SqsDeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn
   - **Data Format:** Newline Delimited (one finding per line)

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack removes the EventBridge rule; findings stop reaching this bucket.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send EKS control-plane logs from a busy cluster, through Firehose

**Fits when:** A cluster's control-plane logs (audit above all) are in CloudWatch Logs at a rate an API read cannot keep up with.

**Why this way:** A subscription filter streams the log group to Firehose, which decompresses it and writes plain log lines to a bucket that notifies a queue. Nothing polls the Logs API.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=2.1). To send someone this plan, share this link.

**Not chosen:** The CloudWatch Logs API read: one role instead of six resources, and the right choice for a quiet cluster.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, with the Region your logs are in. The last command tells you whether a bucket already announces new files to a queue: a QueueConfigurations entry means it does.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region <your-region>
   bash discover.sh --all-regions trails streams loggroups
   aws s3api get-bucket-notification-configuration --bucket <bucket>
   ```

   **Check:** The output starts with Account: and your 12-digit account ID, then one section per resource type. A trail under CloudTrail trails, or a bucket you recognise as a log bucket, means those logs are already in S3: answer Already landing in an S3 bucket below.

2. **Foundation.** Abstract admin, in Abstract console.

   Start adding the integration named below and choose Role Based Authentication. On the Generate Assume Role Authentication step, copy the External ID, and Abstract's 12-digit AWS account ID from the role that step generates (the account its trust policy names). Put both in one record the cloud admin can read, such as an entry in a shared secrets vault, never chat or email. The cloud admin needs nothing else from Abstract and no Abstract login.

   *Note:* The form also asks for the bucket and the queue, which the stack creates in the next step, so you finish this form in the Verify step. If the form shows a different External ID when you come back, nobody redeploys: the Verify step changes the stack to match.

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **Authentication Type:** Role Based Authentication
   - **External ID:** Copy it into the shared record and leave it as it is

   **Check:** The shared record holds a 12-digit AWS account ID and an External ID, and the cloud admin has confirmed they can open it.

3. **Set up.** Cloud admin, in CloudShell.

   Turn on control-plane logging for the log types you need, if it is not on yet (audit is the one that matters for security). Then run the EKS template's deploy.sh with the two values from the shared record and the cluster name.

   > **This changes:** Adds a subscription filter to the cluster's log group. A log group takes at most two, so the stack fails if two already exist. Turning on control-plane logging bills CloudWatch Logs ingestion.

   Template: [EKS control-plane logs to Abstract: Firehose to S3](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-eks-control-plane-logs)

   ```bash
   aws logs describe-subscription-filters --log-group-name /aws/eks/<cluster-name>/cluster
   aws s3 ls s3://<BucketNameOut>/eks/ --recursive | tail -5
   ```

   **Check:** The stack shows CREATE_COMPLETE, the first command lists the filter, and the second lists objects under eks/.

4. **Verify.** Abstract admin, then cloud admin, in Abstract console, then AWS CloudShell.

   Open the integration you started in the Foundation step and fill it in from the stack's Outputs tab (CloudFormation, your stack, Outputs), as the table shows. Before you save, compare the External ID on the form with the one in the shared record. If they differ, do not start over: the cloud admin updates the stack (CloudFormation, your stack, Update, Use existing template, set External ID to the value the form shows, Submit), and you save once the stack shows UPDATE_COMPLETE. Then the cloud admin runs the commands with the values from the Outputs tab.

   *Note:* Abstract has no ready-made EKS audit parser, so events arrive unparsed until your Abstract team adds one. If nothing arrives at all, a growing queue means the role ARN or External ID on the form does not match the stack.

   ```bash
   aws sqs get-queue-attributes --queue-url <SqsQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   aws sqs get-queue-attributes --queue-url <SqsDeadLetterQueueUrl> --attribute-names ApproximateNumberOfMessagesVisible
   ```

   In Abstract, add the **AWS S3 SQS Source** integration and fill in:

   - **SQS URL:** SqsQueueUrl
   - **AWS Region:** AwsRegion
   - **Authentication Type:** Role Based Authentication
   - **S3 Bucket:** BucketNameOut
   - **AWS SQS Queue ARN:** SqsQueueArn
   - **External ID:** The value in the shared record; it must match the stack's External ID
   - **Assume Role ARN:** RoleArn
   - **Data Format:** Newline Delimited (one log line per line)

   **Check:** Within 15 minutes of a new log file landing, the queue's ApproximateNumberOfMessagesVisible goes back to 0 (Abstract is taking the messages), the dead-letter queue stays at 0, and a search in Abstract over the last 15 minutes for this integration's events returns results.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack; Launch Stack names it abstract- plus the template name without aws-, for example abstract-source-cloudtrail-s3-sqs. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   > **This changes:** Deleting the stack removes the subscription filter from the cluster's log group; control-plane logging stays on and keeps billing until you turn it off.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Other templates

No plan above needs these on their own.

- [AWS helper: look up resources and switch on logging](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-foundation-log-delivery-helper): A support stack. Deploy it only when another stack needs a lookup CloudFormation cannot do by name (a KMS alias, a queue name, a web ACL name), or to switch on S3 or load balancer access logging for resources you already have.
- [CloudWatch metrics to Abstract: read-only role](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-access-cloudwatch-metrics-role): Metrics, not logs. Deploy it only when you also want CloudWatch metrics in Abstract, usually for correlation; it is one read-only role with no bucket or queue, and no log source depends on it.
- [Abstract to your S3 bucket: write-only export role](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-destination-s3-export-role): The other direction. Deploy it only when Abstract should write its normalized events out to a bucket of yours (the S3 Export destination); it is a write role for one bucket and prefix, and no source plan needs it.
- [Dead-letter queue alarms: email when Abstract cannot read](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-monitoring-sqs-dead-letter-alarms): After any S3 + SQS plan, before go-live. Each source template creates a dead-letter queue but alarms on it only when asked; this one alarms on up to ten existing dead-letter queues at once, so an object Abstract cannot read (AccessDenied, a KMS refusal) is seen in minutes instead of when retention expires.

## Not covered yet

- EventBridge routing exists only as Terraform (the shared-bucket template); there is no Launch Stack version.
- Firehose delivery for high-volume CloudWatch Logs exists only for EKS control-plane logs; other log groups and WAF have no Firehose template yet.
- Reading several sources from one queue with a single parser is parser work in Abstract, not a template.
- Several integrations sharing one External ID (multiple sources, StackSet, shared bucket) is not yet proven against the Abstract console; each template's role takes a single External ID.
- Abstract's Security Lake integration reads WAF records only; Security Lake subscribers for other sources have no matching integration yet.
- Network Firewall, AWS Config, Security Hub and EKS audit records have no ready-made parser in Abstract.
