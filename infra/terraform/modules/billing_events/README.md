# modules/billing_events

Terraform for the **event wiring** of the two BioMate billing Lambdas. The
Lambda *code* is deployed by `backend/lib/galaxy/ai/billing/lambda/Makefile`
(`make s3`, `make batch`) or the `deploy_*.sh` scripts; this module wires the
*triggers* that were previously configured by hand and had silently broken
(live billing showed `storage: $0` because the S3 → SQS → Lambda path was never
created).

## What it creates

| Path | Resources |
|------|-----------|
| **S3 storage metering** | SQS queue + DLQ, queue policy, per-bucket `s3:ObjectCreated:*`/`s3:ObjectRemoved:*` notification, SQS→Lambda event source mapping |
| **Batch compute metering** | EventBridge rule (`source=aws.batch`, `Batch Job State Change`), Lambda target, invoke permission |

## What it does NOT create (pass these in / manage elsewhere)

- The Lambda **functions** — deploy first with `make s3` / `make batch`
  (`backend/lib/galaxy/ai/billing/lambda/`).
- The Lambda **IAM execution roles** — created by `deploy_s3_lambda.sh` /
  `deploy_batch_lambda.sh`.
- The **S3 buckets** and the **ElastiCache Redis** / **Secrets Manager** secrets
  the functions read at runtime.

## Prereq: functions must exist first

This module references the functions by name to attach the event source mapping,
target, and permission. `terraform apply` will fail if the functions have not
been deployed. Order:

1. `cd backend/lib/galaxy/ai/billing/lambda && make s3 batch`
2. `terraform apply` this module.

## Usage

```hcl
module "billing_events" {
  source     = "../../modules/billing_events"
  env        = "prod"
  aws_region = "us-west-2"
  account_id = "399683337364"
  # Defaults already match the deployed function/queue/rule names and the two
  # billable buckets (biomate-nextflow-work + biomate-production). Override
  # metered_buckets / *_function_name only if your deployment diverges.
}
```

## Verification & gotchas

See `docs/20260804_BILLING_LAMBDA_WIRING_RUNBOOK.md` for the equivalent raw
`aws` CLI commands (create-queue, put-bucket-notification-configuration,
create-event-source-mapping, events put-rule/put-targets, lambda add-permission),
the end-to-end verification (test S3 put → `/api/billing/usage` storage > 0), and
the **user-attribution mismatch** that can misroute upload storage costs.
