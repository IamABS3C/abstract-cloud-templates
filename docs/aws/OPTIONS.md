# How logs reach Abstract on AWS: the options explained

[The setup guide](GUIDE.md) picks one of these for you. This page explains what each option is, so the
choice makes sense.

## The one rule behind everything

Abstract reads an S3 source through **an SQS queue**. Each message on the queue says "a new log file
landed at this key", and Abstract fetches that file. An integration has no prefix or path filter of its
own: **what is on the queue is what that integration reads**, and each integration has one parser. So:

- **One source, one queue.** CloudTrail and VPC Flow Logs need different parsers, so they need different
  queues, even if they share a bucket.
- **Never two readers on one queue.** SQS gives each message to exactly one reader. Two Abstract
  integrations on one queue, or Abstract plus another SIEM, each get a random part of the files, and
  nothing reports an error. In a measured test, two readers on one queue received 16 of 20 files between
  them, and 4 were lost.

Everything below is a way of getting the right "new file" message onto the right queue.

## Routing options, simplest first

| Option | Template setting | Use it when | Avoid it when |
|---|---|---|---|
| **S3 → SQS** (direct) | `NotificationPath = S3ToSQS`, or `routing_mode = direct` | Only Abstract needs the events, and each source sits under its own prefix. The default. | Something else needs the same events. |
| **S3 → SNS → SQS** (fan-out) | `NotificationPath = S3ToSNSToSQS`, or `routing_mode = sns` | Another consumer (a second SIEM, a Lambda function, a data lake) needs the same new-file events. | Nothing else needs them: SNS is one more hop to secure. |
| **Trail → SNS → SQS** | Built into the CloudTrail template | CloudTrail. The trail announces each file it writes through SNS. | (CloudTrail always uses this.) |
| **S3 → EventBridge → SQS** | `routing_mode = eventbridge` (Terraform only) | Another team owns the bucket's notifications, the list of sources keeps growing, or you need to filter on more than prefix and suffix. | A simple, stable setup: it adds a rule per source. |

### Why fan-out exists

S3 sends each event to **one** destination per matching rule, so it cannot copy one event to two queues.
SNS takes that one event and copies it to every subscriber. Use it when you would otherwise be tempted to
point a second tool at Abstract's queue.

### Why EventBridge exists

A bucket has exactly **one** notification configuration, and every write replaces all of it. A team
adding its own notification can remove yours without an error, and vice versa. With EventBridge
switched on, the bucket sends every event to EventBridge once, and each source becomes its own rule. You
add a source by adding a rule, without touching the bucket's settings. Take care when switching it on:
writing only the EventBridge flag, with nothing else, removes every existing queue and topic notification
on that bucket.

## Things that surprise people

- **Notifications are not retroactive.** Only files written after the notification exists are announced.
  Files already in the bucket are not read.
- **The first message on a new queue is a test.** S3 puts one `s3:TestEvent` on the queue when a
  notification is set up. Abstract logs it as "not a valid S3 notification". That is harmless, and it
  proves the notification works.
- **Encrypted queues need a key policy grant.** If the queue uses your own KMS key, the sending service
  (S3, SNS or EventBridge) must be allowed to use the key in the **key policy**. Without it, the events
  are dropped and nothing reports an error.
- **The S3 → SQS hop has no dead-letter queue.** If the queue policy or key grant is wrong, S3 retries and
  then drops the event. That is why each template verifies the path with a test file.
- **Archived files cannot be read.** A lifecycle rule that moves files to Glacier or Deep Archive before
  Abstract reads them breaks ingestion, often months after it started working.
- **Duplicates are possible.** S3 delivers each event at least once, so an occasional duplicate is normal
  in every routing option.

## Sources that are not S3

| Where the logs are | Option |
|---|---|
| CloudWatch Logs | Abstract reads the log groups by API. Fine at modest volume; at high volume, streaming through Firehose to S3 costs less, and has no template yet. |
| A Kinesis data stream | Abstract reads the stream directly. No bucket or queue. |
| Amazon Security Lake | Abstract subscribes as a Security Lake subscriber. |

## Many accounts

- **CloudTrail:** one organization trail in the management account covers every account, including new
  ones. Don't deploy a trail per account.
- **Any other source:** the organization StackSet rolls the same source stack into every account of an
  organizational unit. Each account gets its own bucket, queue and role, and its own integration in
  Abstract.
