# Set up AWS

<!-- Generated from tools/guides/aws.yml by `python -m tools.templates generate`. Do not edit. -->

For each log source you end up with three things in your AWS account: somewhere the logs land, an SQS queue (or a stream) that announces each new file, and an IAM role only Abstract can assume, with an External ID. Abstract polls the queue and reads the files. You start in Abstract, deploy one stack in AWS with the values Abstract gives you, then paste the stack's outputs back into Abstract.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up. The same questions are in the [onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws), which gives each plan a link you can share.

## Where are your logs today?

- **Already landing in an S3 bucket** → [What is in that bucket?](#what-is-in-that-bucket)
- **Not in S3 yet. I want to start collecting an AWS service's logs** → [How many AWS accounts?](#how-many-aws-accounts)
  CloudTrail, VPC Flow Logs, WAF, load balancer, CloudFront, Route 53 Resolver, S3 access logs, or anything you write to S3.
- **In CloudWatch Logs** → [What is in the log group, and how busy is it?](#what-is-in-the-log-group-and-how-busy-is-it)
- **In a Kinesis data stream** → [Let Abstract read a Kinesis data stream](#let-abstract-read-a-kinesis-data-stream)
- **In Amazon Security Lake** → [Make Abstract a Security Lake subscriber](#make-abstract-a-security-lake-subscriber)
- **In an AWS security service's own console** → [Which security service?](#which-security-service)
  GuardDuty findings, Security Hub findings, Network Firewall logs or AWS Config history that no bucket of yours receives yet.

## What is in the log group, and how busy is it?

- **Any log group at modest volume** → [Let Abstract read CloudWatch Logs directly](#let-abstract-read-cloudwatch-logs-directly)
- **EKS control-plane logs from a busy cluster** → [Send EKS control-plane logs from a busy cluster, through Firehose](#send-eks-control-plane-logs-from-a-busy-cluster-through-firehose)
  Audit logging on a busy cluster outruns an API read; Firehose takes the whole stream.

## Which security service?

If Security Lake already collects it, choose In Amazon Security Lake instead; one subscriber covers several of these.

- **GuardDuty findings** → [Send GuardDuty findings, through an encrypted bucket](#send-guardduty-findings-through-an-encrypted-bucket)
- **Security Hub findings** → [Send Security Hub findings, through EventBridge and Firehose](#send-security-hub-findings-through-eventbridge-and-firehose)
- **Network Firewall alert, flow or TLS logs** → [Send AWS Network Firewall logs, one queue per log type](#send-aws-network-firewall-logs-one-queue-per-log-type)
- **AWS Config configuration history** → [Send AWS Config configuration history, through a new bucket](#send-aws-config-configuration-history-through-a-new-bucket)

## What is in that bucket?

- **One source, and the bucket already notifies an SQS queue** → [Let Abstract read logs you already collect, with a read-only role](#let-abstract-read-logs-you-already-collect-with-a-read-only-role)
- **Several sources under different prefixes, or no queue yet** → [Who owns the bucket's event notifications, and does anything else read them?](#who-owns-the-buckets-event-notifications-and-does-anything-else-read-them)
  Each source needs its own queue, because each needs its own parser in Abstract.

## Who owns the bucket's event notifications, and does anything else read them?

S3 sends each event to only one place per prefix, and replacing a bucket's notification settings removes everyone else's.

- **My team owns them, and only Abstract needs the events** → [One queue per source, for a bucket you already have](#one-queue-per-source-for-a-bucket-you-already-have)
- **Other systems also need the same events** → [One queue per source, for a bucket other systems also read](#one-queue-per-source-for-a-bucket-other-systems-also-read)
- **Another team owns them, or the list of sources keeps growing** → [One queue per source, routed by EventBridge](#one-queue-per-source-routed-by-eventbridge)

## How many AWS accounts?

- **One account** → [How many sources in this account?](#how-many-sources-in-this-account)
- **Every account in an organizational unit** → [Which source, across the organization?](#which-source-across-the-organization)

## Which source, across the organization?

- **CloudTrail** → [Send CloudTrail from every account in your organization](#send-cloudtrail-from-every-account-in-your-organization)
  One organization trail covers every account, including ones added later.
- **Another source, in every account** → [Start collecting one source in every account of an organizational unit](#start-collecting-one-source-in-every-account-of-an-organizational-unit)

## How many sources in this account?

- **One** → [Does anything besides Abstract need to know when a new log file lands?](#does-anything-besides-abstract-need-to-know-when-a-new-log-file-lands)
- **Several** → [Start collecting several AWS sources in one account, in one deploy](#start-collecting-several-aws-sources-in-one-account-in-one-deploy)

## Does anything besides Abstract need to know when a new log file lands?

- **No, only Abstract (most common)** → [Start collecting one AWS log source, with a new bucket and queue](#start-collecting-one-aws-log-source-with-a-new-bucket-and-queue)
- **Yes, another SIEM, a Lambda function or a data lake** → [Start collecting one AWS log source, with SNS fan-out](#start-collecting-one-aws-log-source-with-sns-fan-out)

## Start collecting one AWS log source, with a new bucket and queue

**Fits when:** The source is not writing to S3 yet, and only Abstract needs the notifications.

**Why this way:** The fewest moving parts. The stack creates the bucket, switches on the logging where AWS allows it, and has the bucket notify the queue directly.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.0.0). To send someone this plan, share this link.

**Not chosen:** SNS fan-out: nothing else needs the notifications.

**Not chosen:** EventBridge: one stable source does not need its filtering.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console.

   Launch the stack for your source with the two values from Abstract. Leave Notification routing at S3ToSQS, the default. CloudTrail always goes trail to SNS to SQS, which is right for it.

   Templates, one per source:

   - [CloudTrail to Abstract: new trail, bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudtrail-s3-sqs)
   - [VPC Flow Logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-vpc-flow-logs-s3-sqs)
   - [WAF logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-waf-logs-s3-sqs)
   - [Load balancer logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-load-balancer-logs-s3-sqs)
   - [CloudFront logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudfront-logs-s3-sqs)
   - [Route 53 DNS logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-route53-resolver-logs-s3-sqs)
   - [S3 access logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-s3-access-logs-s3-sqs)
   - [Any S3 logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-generic-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE and its Outputs tab lists the role, queue and bucket.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Start collecting one AWS log source, with SNS fan-out

**Fits when:** The source is not writing to S3 yet, and another consumer needs the same new-file notifications.

**Why this way:** S3 can send one prefix's events to only one destination. SNS takes that one and fans it out, so Abstract and the other consumer each get their own copy.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.0.1). To send someone this plan, share this link.

**Not chosen:** Direct S3 to SQS: the other consumer would have nothing to subscribe to.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console.

   Launch the stack for your source with the two values from Abstract, and Notification routing set to S3ToSNSToSQS. Then subscribe the other consumer to the SNS topic the stack outputs. For CloudTrail, use the CloudTrail template: it already publishes through SNS.

   Templates, one per source:

   - [VPC Flow Logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-vpc-flow-logs-s3-sqs)
   - [WAF logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-waf-logs-s3-sqs)
   - [Load balancer logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-load-balancer-logs-s3-sqs)
   - [CloudFront logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudfront-logs-s3-sqs)
   - [Route 53 DNS logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-route53-resolver-logs-s3-sqs)
   - [S3 access logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-s3-access-logs-s3-sqs)
   - [Any S3 logs to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-generic-s3-sqs)

   Set: `NotificationPath` = `S3ToSNSToSQS`

   **Check:** The stack shows CREATE_COMPLETE and its outputs include SnsTopicArn.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Start collecting several AWS sources in one account, in one deploy

**Fits when:** You want several sources in the same account and Region, with the identity and encryption set once.

**Why this way:** One master stack nests the per-source stacks, so every source gets its own bucket, queue and role from a single launch.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.0.1). To send someone this plan, share this link.

**Not chosen:** One stack per source: more launches for the same result.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console.

   Launch the master stack with the values from Abstract and switch on the sources you want. Each source is its own nested stack with its own outputs, and each needs its own integration in Abstract. Every nested role trusts the one External ID the master stack was given, so each integration must be saved with that same External ID, not a new one.

   *Note:* If the integration form shows a new External ID and will not take yours, the extra integrations cannot assume their roles. Deploy one per-source stack per integration instead.

   Template: [Several AWS sources to Abstract in one deploy](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-multiple-sources-one-bucket)

   **Check:** The master and every nested stack show CREATE_COMPLETE.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send CloudTrail from every account in your organization

**Fits when:** You use AWS Organizations and want API activity from every account, including accounts added later.

**Why this way:** One organization trail, deployed once in the management account, already covers every member account. Abstract reads one bucket.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.1.0). To send someone this plan, share this link.

**Not chosen:** A StackSet with one trail per account: many trails and buckets for what one organization trail does.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console, in the management account.

   Launch the CloudTrail stack in the management account (or a delegated administrator account) with the values from Abstract, Is organization trail set to true, and your organization ID.

   Template: [CloudTrail to Abstract: new trail, bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudtrail-s3-sqs)

   Set: `CtIsOrganizationTrail` = `true`

   **Check:** In CloudTrail, the trail shows as an organization trail, and log files arrive under each account's prefix.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Start collecting one source in every account of an organizational unit

**Fits when:** The same source, such as VPC Flow Logs, should exist in every account of an organizational unit, including accounts added later.

**Why this way:** A service-managed StackSet rolls the source's stack into each account and Region, and into accounts added to the unit later.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=1.1.1). To send someone this plan, share this link.

**Not chosen:** Deploying account by account: slow, and new accounts are missed.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell, in the management account.

   Run the StackSet's deploy.sh from the management account or a delegated StackSets administrator, naming the source template, the organizational unit and the Regions. Each account gets its own bucket, queue and role, and every role trusts the one External ID you deploy with; add one integration per account in Abstract with that account's outputs and that same External ID.

   Template: [One AWS source in every account: organization StackSet](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-s3-sqs-organization-stackset)

   **Check:** Every stack instance in the StackSet shows CURRENT.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then CloudShell in the management account.

   Delete the integrations in Abstract first. Then remove the stack instances from every account, wait for that operation to finish, and delete the StackSet. The StackSet is named abstract- plus the source, for example abstract-vpc-flow-logs-s3-sqs. Each account's log bucket is kept; empty and delete it there if you no longer need the logs.

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

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console.

   Launch the read role stack with the values from Abstract, your bucket name and your queue's ARN.

   *Note:* Never point a second integration at the same queue. SQS hands each message to only one reader, so two readers would each get a random half, with no error.

   Template: [Existing S3 logs to Abstract: read-only access role](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-access-read-role-existing-bucket-and-queue)

   **Check:** The stack shows CREATE_COMPLETE and outputs RoleArn.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## One queue per source, for a bucket you already have

**Fits when:** One bucket holds several sources under different prefixes, your team owns its notifications, and only Abstract needs them.

**Why this way:** Each prefix notifies its own queue directly, so each source gets its own parser in Abstract.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.1.0). To send someone this plan, share this link.

**Not chosen:** SNS or EventBridge: nothing else needs the events.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell, with Terraform.

   Deploy the shared-bucket template with routing_mode = direct and manage_bucket_notification = false, listing each source's prefix. A bucket has one notification configuration and every write replaces all of it, so Terraform does not write it: merge the queue entries from the bucket_notification_plan output into the bucket's existing notifications yourself, keeping everything already there.

   Template: [Shared S3 bucket to Abstract: one queue per source](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-existing-bucket-queues)

   Set: `routing_mode` = `direct`, `manage_bucket_notification` = `False`

   **Check:** terraform apply completes, and the output abstract_configurations lists one queue per source.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin, Abstract admin and the bucket owner, in Abstract console, then CloudShell with Terraform.

   Delete the integrations in Abstract first, so they stop polling. Then the bucket owner removes the entries they merged into the bucket's notifications (or switches EventBridge off, if nothing else uses it). Then destroy, in the same folder and with the same state. Your bucket and its logs are never touched.

   ```bash
   terraform destroy
   ```

   **Check:** terraform destroy completes, and the bucket's notification configuration no longer names an Abstract queue.

## One queue per source, for a bucket other systems also read

**Fits when:** One bucket holds several sources, and other systems need the same events.

**Why this way:** The bucket notifies one SNS topic, and each source's queue subscribes with a filter, so the other systems can subscribe too.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.1.1). To send someone this plan, share this link.

**Not chosen:** Direct notifications: they would take the events away from the other systems.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell, with Terraform.

   Deploy the shared-bucket template with routing_mode = sns and manage_bucket_notification = false, listing each source's prefix. Then add the topic entry from the bucket_notification_plan output to the bucket's notifications, keeping the existing ones, and move the other systems onto the topic when they are ready.

   Template: [Shared S3 bucket to Abstract: one queue per source](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-existing-bucket-queues)

   Set: `routing_mode` = `sns`, `manage_bucket_notification` = `False`

   **Check:** terraform apply completes, and each source's queue is subscribed to the topic.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin, Abstract admin and the bucket owner, in Abstract console, then CloudShell with Terraform.

   Delete the integrations in Abstract first, so they stop polling. Then the bucket owner removes the entries they merged into the bucket's notifications (or switches EventBridge off, if nothing else uses it). Then destroy, in the same folder and with the same state. Your bucket and its logs are never touched.

   ```bash
   terraform destroy
   ```

   **Check:** terraform destroy completes, and the bucket's notification configuration no longer names an Abstract queue.

## One queue per source, routed by EventBridge

**Fits when:** Another team owns the bucket's notifications, or the list of sources keeps growing and needs richer filtering.

**Why this way:** EventBridge rules filter on more than prefix and suffix, and adding a source adds a rule instead of rewriting the bucket's settings.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=0.1.2). To send someone this plan, share this link.

**Not chosen:** Direct notifications: you cannot safely edit a bucket another team owns.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell, with Terraform.

   Deploy the shared-bucket template with routing_mode = eventbridge and manage_bucket_notification = false, listing each source's prefix. Then give the bucket owner the manual_bucket_steps output: it switches on EventBridge for the bucket while keeping every existing notification. Switching it on with nothing else in the request removes them all.

   Template: [Shared S3 bucket to Abstract: one queue per source](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-existing-bucket-queues)

   Set: `routing_mode` = `eventbridge`, `manage_bucket_notification` = `False`

   **Check:** terraform apply completes, and eventbridge_rule_arns lists one rule per source.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin, Abstract admin and the bucket owner, in Abstract console, then CloudShell with Terraform.

   Delete the integrations in Abstract first, so they stop polling. Then the bucket owner removes the entries they merged into the bucket's notifications (or switches EventBridge off, if nothing else uses it). Then destroy, in the same folder and with the same state. Your bucket and its logs are never touched.

   ```bash
   terraform destroy
   ```

   **Check:** terraform destroy completes, and the bucket's notification configuration no longer names an Abstract queue.

## Let Abstract read CloudWatch Logs directly

**Fits when:** The logs are in CloudWatch Logs, at modest volume.

**Why this way:** Abstract reads the log groups by API. Nothing is copied to S3.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=2.0). To send someone this plan, share this link.

**Not chosen:** Exporting to S3 first: worth it only at high volume.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console.

   Launch the CloudWatch Logs stack with the values from Abstract, naming the log groups Abstract may read.

   *Note:* For high-volume log groups, API reads cost more than a subscription to a stream. EKS control-plane logs have a Firehose template; other log groups do not yet.

   Template: [CloudWatch Logs to Abstract: direct API read](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-cloudwatch-logs-api)

   **Check:** The stack shows CREATE_COMPLETE and outputs RoleArn.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

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

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console.

   Launch the Kinesis stack with the values from Abstract. Choose your existing stream, or let it create one.

   Template: [Kinesis stream to Abstract: direct stream read](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-kinesis-stream)

   **Check:** The stack shows CREATE_COMPLETE and outputs the stream ARN and RoleArn.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Make Abstract a Security Lake subscriber

**Fits when:** Your logs are centralised in Amazon Security Lake.

**Why this way:** Abstract subscribes to Security Lake and is notified of each new object, without a bucket of your own.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=4). To send someone this plan, share this link.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in AWS console, in the Security Lake delegated administrator account.

   Launch the Security Lake stack. Give Abstract's account as a bare 12-digit account ID, not an ARN.

   Template: [Security Lake to Abstract: subscriber and SQS notification](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-security-lake)

   **Check:** In Security Lake, the subscriber shows as active.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE.

## Send GuardDuty findings, through an encrypted bucket

**Fits when:** GuardDuty is on in this Region and its findings should reach Abstract.

**Why this way:** GuardDuty exports findings only to S3, and only under a customer managed KMS key. The stack creates the key, the bucket, the queue and the role, and points your detector's export at the bucket.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.0). To send someone this plan, share this link.

**Not chosen:** Security Hub or Security Lake: worth it only if you collect those anyway; a second path duplicates every finding.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell, in the GuardDuty delegated administrator account for an organization.

   Run the GuardDuty template's deploy.sh with the values from Abstract and your detector ID. If the detector already exports to another bucket, set CreatePublishingDestination to false and decide which export to keep. Then set the detector's finding-update frequency to 15 minutes, or updated findings lag the console by up to six hours.

   Template: [GuardDuty findings to Abstract: new key, bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-guardduty-findings-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE, and list-publishing-destinations shows the bucket as PUBLISHING.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the stack; that also removes the detector's export to the bucket. The bucket and the KMS key are kept on purpose, because the findings in the bucket are encrypted under that key: empty and delete the bucket first, and only then schedule the key for deletion.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE and list-publishing-destinations no longer lists the bucket.

## Send AWS Network Firewall logs, one queue per log type

**Fits when:** An AWS Network Firewall has no logging yet, and its alert (and flow or TLS) logs should reach Abstract.

**Why this way:** Alert, flow and TLS logs are three different record shapes. The stack logs each to its own prefix and notifies its own queue, so each gets its own configuration and parser in Abstract.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.2). To send someone this plan, share this link.

**Not chosen:** One queue for all three types: mixed shapes in one configuration parse badly.

**Not chosen:** A bucket you already log to: use the shared-bucket template's per-prefix queues instead.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell.

   Run the Network Firewall template's deploy.sh with the values from Abstract and your firewall's ARN. Alert logs are always on; choose flow and TLS logs. Later, switch one log type per stack update: Network Firewall accepts only one logging change at a time.

   *Note:* Add one AWS S3 SQS Source integration in Abstract per log type you turned on, each with that type's queue, dataformat nd and the same External ID.

   Template: [Network Firewall logs to Abstract: bucket and three queues](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-network-firewall-logs-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE, and describe-logging-configuration lists the bucket for each type you chose.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integrations in Abstract first, so they stop polling. Then delete the stack; that also turns the firewall's logging off. The log bucket is kept on purpose: empty it in the S3 console, then delete it.

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

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell.

   Run the AWS Config template's deploy.sh with the values from Abstract. Leave CreateDeliveryChannel at false when the account already has a delivery channel (most do), then repoint that channel at the new bucket with put-delivery-channel, as the template's prerequisites show.

   *Note:* In Abstract, set dataformat json and json_key configurationItems; AWS Config needs a custom parser, because Abstract has no managed AWS Config integration.

   Template: [AWS Config history to Abstract: new bucket and queue](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-config-history-s3-sqs)

   **Check:** The stack shows CREATE_COMPLETE, and describe-delivery-channels names the new bucket.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Repoint the delivery channel at its old bucket if you moved it (a channel the stack created is deleted with the stack, and AWS Config then delivers nothing). Then delete the stack. The bucket is kept on purpose: empty it, then delete it.

   ```bash
   aws cloudformation delete-stack --stack-name <your-stack-name>
   aws cloudformation wait stack-delete-complete --stack-name <your-stack-name>
   ```

   **Check:** The stack shows DELETE_COMPLETE, and describe-delivery-channels names the bucket you want.

## Send Security Hub findings, through EventBridge and Firehose

**Fits when:** Security Hub (or Security Hub CSPM) is on, Security Lake is not, and its findings should reach Abstract.

**Why this way:** Security Hub sends findings only to EventBridge. The stack routes them through Firehose into a bucket, one finding per line, and notifies a queue Abstract polls.

[Open this plan in the onboarding app](https://main.d3lmkfjwtkmxi3.amplifyapp.com/setup/aws?a=5.1). To send someone this plan, share this link.

**Not chosen:** Security Lake: the better path if you run it, since one subscriber covers Security Hub and more.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell, in the Security Hub administrator account's aggregation Region.

   Run the Security Hub template's deploy.sh with the values from Abstract. Choose the finding events: "Security Hub Findings - Imported" for Security Hub CSPM (ASFF), or "Findings Imported V2" for Security Hub (OCSF). For both, deploy the stack twice with different name prefixes, one per shape.

   *Note:* In Abstract, set dataformat nd and use a parser for the shape you chose; there is no managed Security Hub integration.

   Template: [Security Hub findings to Abstract: EventBridge and Firehose](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-security-hub-findings-firehose)

   **Check:** The stack shows CREATE_COMPLETE, and objects appear under securityhub/ after the next finding update.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

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

**Not chosen:** Security Lake: the better path if you run it; EKS audit logs are a native source there.

1. **Check first.** Cloud admin, in AWS CloudShell.

   Take stock first. The discovery script is read-only: it lists the buckets, SQS queues, trails, KMS keys, Kinesis streams and log groups you already have, so you can tell whether your logs already land somewhere Abstract can read.

   *Note:* Run it in the account you will deploy to, and set --region to the Region your logs are in.

   ```bash
   curl -fsSLO https://raw.githubusercontent.com/IamABS3C/abstract-cloud-templates/main/tools/aws-template-publisher/discover.sh
   bash discover.sh --region us-east-1
   bash discover.sh --all-regions trails streams loggroups
   ```

   **Check:** You know whether the logs are already in S3, CloudWatch Logs, Kinesis or Security Lake.

2. **Foundation.** Abstract admin, in Abstract console.

   Add the integration for your source in Abstract and choose IAM role authentication. Copy the two values it shows: Abstract's AWS account ID and the External ID. Keep the page open until the last step; starting again creates a new External ID, and the role you deploy would no longer match.

3. **Set up.** Cloud admin, in CloudShell.

   Turn on control-plane logging for the log types you need, if it is not on yet (audit is the one that matters for security). Then run the EKS template's deploy.sh with the values from Abstract and the cluster name.

   *Note:* In Abstract, set dataformat nd and use a parser for EKS audit JSON; there is no managed EKS integration.

   Template: [EKS control-plane logs to Abstract: Firehose to S3](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-source-eks-control-plane-logs)

   **Check:** The stack shows CREATE_COMPLETE, describe-subscription-filters lists the filter, and objects appear under eks/.

4. **Verify.** Abstract admin, in Abstract console.

   Paste the stack's outputs into the same integration page: the role ARN, the queue URL and ARN (or the stream), the bucket and the Region. Save. Then run the template's own verify steps from its page.

   **Check:** Events from the source appear in Abstract within minutes of new log files landing.

5. **Clean up.** Cloud admin and Abstract admin, in Abstract console, then AWS console.

   Delete the integration in Abstract first, so it stops polling. Then delete the CloudFormation stack. The log bucket is kept on purpose, because it holds your logs: to remove it too, empty it in the S3 console (Empty also removes old versions), then delete it.

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
- Several integrations sharing one External ID (multiple sources, StackSet) is not yet proven against the Abstract console; each template's role takes a single External ID.
