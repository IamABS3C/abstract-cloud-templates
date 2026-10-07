# Set up AWS

<!-- Generated from tools/guides/aws.yml by `python -m tools.templates generate`. Do not edit. -->

For each log source you end up with three things in your AWS account: somewhere the logs land, an SQS queue (or a stream) that announces each new file, and an IAM role only Abstract can assume, with an External ID. Abstract polls the queue and reads the files. You start in Abstract, deploy one stack in AWS with the values Abstract gives you, then paste the stack's outputs back into Abstract.

Answer the questions below. Each answer leads to the next question or to one plan: the steps in order, from checking what you have to cleaning it all up.

## Where are your logs today?

- **Already landing in an S3 bucket** → [What is in that bucket?](#what-is-in-that-bucket)
- **Not in S3 yet. I want to start collecting an AWS service's logs** → [How many AWS accounts?](#how-many-aws-accounts)
  CloudTrail, VPC Flow Logs, WAF, load balancer, CloudFront, Route 53 Resolver, S3 access logs, or anything you write to S3.
- **In CloudWatch Logs** → [Let Abstract read CloudWatch Logs directly](#let-abstract-read-cloudwatch-logs-directly)
- **In a Kinesis data stream** → [Let Abstract read a Kinesis data stream](#let-abstract-read-a-kinesis-data-stream)
- **In Amazon Security Lake** → [Make Abstract a Security Lake subscriber](#make-abstract-a-security-lake-subscriber)

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

   *Note:* For high-volume log groups, API reads cost more than a subscription to a stream. A Firehose route is not templated yet.

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

## Other templates

No plan above needs these on their own.

- [AWS helper: look up resources and switch on logging](https://github.com/IamABS3C/abstract-cloud-templates/tree/main/templates/aws/aws-foundation-log-delivery-helper): A support stack. Deploy it only when another stack needs a lookup CloudFormation cannot do by name (a KMS alias, a queue name, a web ACL name), or to switch on S3 or load balancer access logging for resources you already have.

## Not covered yet

- EventBridge routing exists only as Terraform (the shared-bucket template); there is no Launch Stack version.
- Firehose aggregation for high-volume CloudWatch Logs or WAF has no template yet.
- Reading several sources from one queue with a single parser is parser work in Abstract, not a template.
- Several integrations sharing one External ID (multiple sources, StackSet) is not yet proven against the Abstract console; each template's role takes a single External ID.
