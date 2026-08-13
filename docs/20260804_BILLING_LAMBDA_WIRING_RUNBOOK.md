# Billing Lambda Event-Wiring Runbook (2026-08-04)

Two billing Lambda **handlers** exist and their code is complete, but the AWS
**event wiring** that triggers them was done by hand and is not fully in place.
Symptom in production: **`/api/billing/usage` reports `storage: $0`** — the
S3 → SQS → Lambda path is not flowing.

This runbook gives (A) the Terraform apply path (preferred, IaC), and (B) the
exact `aws` CLI commands (fallback / to understand what TF does), in the order to
run, plus verification and attribution **gotchas**. Every function / bucket /
prefix / env-var referenced is cited to `file:line` so nothing is guessed.

> **DO NOT run any mutating command in this doc unless you are intentionally
> wiring the environment.** This file is documentation; the coordinator decides
> when to apply.

---

## 0. The two Lambdas and what they need

| Lambda | Handler | Trigger it needs | Records to |
|--------|---------|------------------|-----------|
| **S3 storage metering** | `s3_event_handler.handler` (`backend/lib/galaxy/ai/billing/lambda/s3_event_handler.py:157`) | S3 bucket notification (`ObjectCreated:*`/`ObjectRemoved:*`) → **SQS** → Lambda event source mapping | `POST {BILLING_API_URL}/internal/billing/s3_put` \| `s3_delete` (`s3_event_handler.py:77,138,149`) |
| **Batch compute metering** | `batch_event_handler.handler` (`backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py:225`) | **EventBridge** rule (`source=aws.batch`, detail-type `Batch Job State Change`) → Lambda target | Directly to **Redis** keys `billing:batch:job:{id}`, `cost:{user_id}:month:{YYYY-MM}:total` (`batch_event_handler.py:184,210`) |

### Canonical names (from the checked-in deploy scripts, NOT the Makefile)

| Thing | Value | Evidence |
|-------|-------|----------|
| S3 Lambda function | `biomate-s3-billing-handler` | `deploy_s3_lambda.sh:10` |
| Batch Lambda function | `biomate-batch-billing-handler` | `deploy_batch_lambda.sh:9`, `eventbridge_rules.json:18` |
| SQS queue | `biomate-s3-billing-events` | `deploy_s3_lambda.sh:12` |
| SQS DLQ | `biomate-s3-billing-events-dlq` | `deploy_s3_lambda.sh:13` |
| EventBridge rule | `biomate-batch-job-state-change` | `deploy_batch_lambda.sh:11`, `eventbridge_rules.json:6` |
| Region | `us-west-2` | `deploy_*.sh:7`, `secrets.py:13`, `infra/terraform/envs/*/main.tf:27` |
| Account ID | `399683337364` | `infra/terraform/envs/test/secrets_access.tf:32-33` |

> ⚠️ **Name mismatch — read before you touch anything.** The **Makefile**
> (`backend/lib/galaxy/ai/billing/lambda/Makefile:24-25`) names the functions
> `biomate-batch-billing` / `biomate-s3-billing` (no `-handler`) **and defaults
> the region to `us-east-1`** (`Makefile:14`). The **deploy scripts** name them
> `...-handler` and default to `us-west-2`. These are two different conventions.
> **Before wiring, confirm what is actually deployed:**
> ```bash
> aws lambda list-functions --region us-west-2 \
>   --query "Functions[?contains(FunctionName,'billing')].FunctionName"
> ```
> Use whatever names come back. The Terraform module and the commands below
> assume the `-handler` names + `us-west-2` (the deploy-script convention). If
> `make` created bare names in `us-east-1`, either re-deploy with the scripts or
> override `s3_lambda_function_name` / `batch_lambda_function_name` /
> `aws_region` on the module.

### The TWO buckets that must be metered

| Bucket | Objects | Key prefixes | Evidence |
|--------|---------|--------------|----------|
| `biomate-nextflow-work` | Nextflow outputs + workdir | `nextflow/outputs/{user_id}/{run_id}/…`, `nextflow/work/{user_id}/{run_id}/…` | `nextflow_executor.py:1207,2742,4636,4640,4741,5013` |
| `biomate-production` (`S3_BUCKET_NAME`) | Direct user uploads / project files | `users/{user_id}/uploads/…` | `frontend/server/s3-client.ts:148,203`; `.env.example:40` |

The old `deploy_s3_lambda.sh` wires **only** `biomate-nextflow-work`
(`deploy_s3_lambda.sh:9`). That is why **upload storage was never billed** — the
uploads bucket had no notification at all. **Wire both.**

---

## A. Preferred path — Terraform

A reusable module now exists: **`infra/terraform/modules/billing_events/`**
(`main.tf` + `README.md`). It creates the SQS queue + DLQ + policy, the per-bucket
S3 notifications, the SQS→Lambda mapping, the EventBridge rule + target +
permission — for **both** buckets — with all names defaulted to the values above.

### A.1 Prereq: deploy the function code first

The module references the functions by name; apply fails if they don't exist.

```bash
cd backend/lib/galaxy/ai/billing/lambda
make s3 batch          # or ../infrastructure/deploy_s3_lambda.sh + deploy_batch_lambda.sh
```

Set the functions' env vars (the module does NOT manage function config):

- S3 Lambda: `BILLING_API_URL`, `BILLING_INTERNAL_KEY` (or SM secret
  `biomate/billing/api-key`, `secrets.py:46`), `USER_TAG_NAME=user_id`
  (`s3_event_handler.py:45-47`).
- Batch Lambda: `REDIS_URL` (ElastiCache, `batch_event_handler.py:41`), and —
  only if re-enabling Lago — `BILLING_LAGO_ENABLED=true` + `LAGO_API_URL`
  (`batch_event_handler.py:118,130`). Lago is **off by default** per CLAUDE.md.

### A.2 Add a module block to the target env

The env stacks live at `infra/terraform/envs/<env>/`. Billing Lambdas were
explicitly deferred there (`envs/dev/main.tf:20` "billing Lambdas … deferred").
Add to the chosen env's `main.tf` (e.g. a new `envs/prod/` or the existing
`dev`):

```hcl
module "billing_events" {
  source     = "../../modules/billing_events"
  env        = "prod"          # tags only
  aws_region = "us-west-2"
  account_id = "399683337364"
  # Defaults match the deployed function/queue/rule names + both billable
  # buckets. Override *_function_name / metered_buckets only if you diverge.
}
```

### A.3 Plan and apply

```bash
cd infra/terraform/envs/<env>
terraform init
terraform plan     # review: 1 queue, 1 DLQ, 1 policy, 2 notifications,
                   #         1 mapping, 1 rule, 1 target, 1 permission
terraform apply    # coordinator decides when
```

If the buckets pre-date TF and already carry OTHER notification configs, note
that `aws_s3_bucket_notification` is **authoritative** for the whole bucket — it
replaces any existing notification config. Check first (§C.1) and fold existing
configs into the module (or use the CLI path in §B which can be additive if you
merge manually).

---

## B. Fallback path — raw `aws` CLI (what TF does, in order)

Placeholders: `REGION=us-west-2`, `ACCOUNT=399683337364`. Run in order.

### B.1 S3 → SQS → Lambda

```bash
REGION=us-west-2
ACCOUNT=399683337364
QUEUE=biomate-s3-billing-events
DLQ=biomate-s3-billing-events-dlq
S3_FN=biomate-s3-billing-handler
NF_BUCKET=biomate-nextflow-work
UP_BUCKET=biomate-production        # value of S3_BUCKET_NAME (.env.example:40)

# 1. DLQ, then main queue with redrive (maxReceiveCount 3)
aws sqs create-queue --queue-name "$DLQ" --region "$REGION"
DLQ_ARN="arn:aws:sqs:$REGION:$ACCOUNT:$DLQ"
aws sqs create-queue --queue-name "$QUEUE" --region "$REGION" \
  --attributes "{\"VisibilityTimeout\":\"60\",\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$DLQ_ARN\\\",\\\"maxReceiveCount\\\":\\\"3\\\"}\"}"
QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE" --region "$REGION" --query QueueUrl --output text)
QUEUE_ARN="arn:aws:sqs:$REGION:$ACCOUNT:$QUEUE"

# 2. Queue policy: allow BOTH buckets to SendMessage (deploy_s3_lambda.sh:95-100 x2)
aws sqs set-queue-attributes --queue-url "$QUEUE_URL" --region "$REGION" \
  --attributes "{\"Policy\":\"{\\\"Version\\\":\\\"2012-10-17\\\",\\\"Statement\\\":[{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"s3.amazonaws.com\\\"},\\\"Action\\\":\\\"SQS:SendMessage\\\",\\\"Resource\\\":\\\"$QUEUE_ARN\\\",\\\"Condition\\\":{\\\"StringEquals\\\":{\\\"aws:SourceAccount\\\":\\\"$ACCOUNT\\\"},\\\"ArnLike\\\":{\\\"aws:SourceArn\\\":\\\"arn:aws:s3:::$NF_BUCKET\\\"}}},{\\\"Effect\\\":\\\"Allow\\\",\\\"Principal\\\":{\\\"Service\\\":\\\"s3.amazonaws.com\\\"},\\\"Action\\\":\\\"SQS:SendMessage\\\",\\\"Resource\\\":\\\"$QUEUE_ARN\\\",\\\"Condition\\\":{\\\"StringEquals\\\":{\\\"aws:SourceAccount\\\":\\\"$ACCOUNT\\\"},\\\"ArnLike\\\":{\\\"aws:SourceArn\\\":\\\"arn:aws:s3:::$UP_BUCKET\\\"}}}]}\"}"

# 3. Bucket notifications → SQS, for EACH bucket
#    ⚠️ This REPLACES the bucket's whole notification config — see §C.1 first.
NOTIF="{\"QueueConfigurations\":[{\"QueueArn\":\"$QUEUE_ARN\",\"Events\":[\"s3:ObjectCreated:*\",\"s3:ObjectRemoved:*\"]}]}"
aws s3api put-bucket-notification-configuration --bucket "$NF_BUCKET" --region "$REGION" --notification-configuration "$NOTIF"
aws s3api put-bucket-notification-configuration --bucket "$UP_BUCKET" --region "$REGION" --notification-configuration "$NOTIF"

# 4. SQS → Lambda event source mapping (deploy_s3_lambda.sh:163-167)
aws lambda create-event-source-mapping --function-name "$S3_FN" \
  --event-source-arn "$QUEUE_ARN" --batch-size 10 --region "$REGION"
```

### B.2 EventBridge → Batch Lambda

```bash
RULE=biomate-batch-job-state-change
BATCH_FN=biomate-batch-billing-handler
BATCH_FN_ARN="arn:aws:lambda:$REGION:$ACCOUNT:function:$BATCH_FN"

# 1. Rule (deploy_batch_lambda.sh:107-118; eventbridge_rules.json:8-13)
aws events put-rule --name "$RULE" --state ENABLED --region "$REGION" \
  --event-pattern '{"source":["aws.batch"],"detail-type":["Batch Job State Change"],"detail":{"status":["RUNNING","SUCCEEDED","FAILED"]}}'

# 2. Permission: let EventBridge invoke the Lambda (deploy_batch_lambda.sh:124-131)
aws lambda add-permission --function-name "$BATCH_FN" \
  --statement-id AllowEventBridgeBatchEvents \
  --action lambda:InvokeFunction --principal events.amazonaws.com \
  --source-arn "arn:aws:events:$REGION:$ACCOUNT:rule/$RULE" --region "$REGION"

# 3. Target: rule → Lambda (deploy_batch_lambda.sh:134-137)
aws events put-targets --rule "$RULE" --region "$REGION" \
  --targets "Id=batch-billing-lambda,Arn=$BATCH_FN_ARN"
```

---

## C. Verification (do this after wiring)

### C.1 Pre-check: existing bucket notifications (avoid clobbering)

```bash
aws s3api get-bucket-notification-configuration --bucket biomate-nextflow-work --region us-west-2
aws s3api get-bucket-notification-configuration --bucket biomate-production   --region us-west-2
```

If either already has a `QueueConfigurations` / `LambdaFunctionConfigurations` /
`TopicConfigurations` block, **merge**, don't overwrite. Both the CLI put and the
TF `aws_s3_bucket_notification` resource are authoritative for the entire bucket.

### C.2 Confirm the mappings/rule exist

```bash
# SQS mapping wired + Enabled
aws lambda list-event-source-mappings --function-name biomate-s3-billing-handler --region us-west-2 \
  --query "EventSourceMappings[].{arn:EventSourceArn,state:State}"
# EventBridge rule + target
aws events list-targets-by-rule --rule biomate-batch-job-state-change --region us-west-2
```

### C.3 End-to-end: test S3 put → storage > 0

```bash
# Put a small object under a per-user prefix the handler recognises
#   (s3_event_handler.py:96-103 resolves user_id from users/{id}/... or
#    nextflow/{outputs,work}/{id}/...). Use a REAL user_id so it aggregates.
UID=<real_biomate_user_id>
echo "billing wiring smoke $(date)" > /tmp/bm_billing_probe.txt
aws s3 cp /tmp/bm_billing_probe.txt \
  "s3://biomate-nextflow-work/nextflow/outputs/$UID/wiring-probe/probe.txt" \
  --region us-west-2

# Watch the S3 Lambda fire (CloudWatch)
aws logs tail /aws/lambda/biomate-s3-billing-handler --region us-west-2 --since 5m --follow
#   expect: "S3 PUT user=<UID> bucket=biomate-nextflow-work size=..."  (s3_event_handler.py:137)

# Then confirm the usage API reflects storage (proxied via Node :5000 → Galaxy :8081)
curl -s https://dev-public.biomate.ai/api/billing/usage \
  -H "Authorization: Bearer <token for $UID>" | jq '.storage'
#   expect: storage cost/bytes > 0  (was $0 before wiring)
```

### C.4 Batch path

```bash
# Launch ANY workflow through BioMate (a real Batch job), then:
aws logs tail /aws/lambda/biomate-batch-billing-handler --region us-west-2 --since 15m --follow
#   expect: "Batch job <id> → RUNNING" then "Recorded SUCCEEDED job=... cost=$..."
#   (batch_event_handler.py:238,217)
# And in Redis:
#   HGETALL billing:batch:job:<jobId>   → status/vcpus/cost_usd
#   GET cost:<user_id>:month:<YYYY-MM>:total   (batch_event_handler.py:210)
```

---

## D. Gotchas — user-attribution mismatches

The whole point of metering is charging the **right** user. There are real
prefix/tag inconsistencies that will silently mis-attribute (or drop) storage:

1. **Uploads tag is `bm_`-prefixed but the key path is not — split identity.**
   `frontend/server/s3-client.ts:19` tags uploaded objects with
   `user_id = bm_${userId}`, while the key path is `users/${userId}/uploads/…`
   (`s3-client.ts:148,203`) using the **raw** `userId`. The S3 handler prefers
   the **tag** over the path (`s3_event_handler.py:113-119`), so uploads bill to
   **`bm_<id>`**. But Nextflow output objects are tagged with the **raw** id
   (`_tag_s3_outputs`, `nextflow_executor.py:3789` → `user_id` unprefixed) and
   the Batch compute path uses the raw id too (`billing_user_id = _uid_for_path`,
   `nextflow_executor.py:4729,5256`; injected as `BIOMATE_USER_ID`,
   `nextflow_executor.py:2535`). **Net effect: the same human is billed under two
   ledger keys** — `bm_<id>` (uploads) and `<id>` (compute + Nextflow storage).
   The `/api/billing/usage` total for a user may under-count unless the reader
   normalizes both. **Fix at the source**: make `s3-client.ts` tag the raw
   `userId` (drop the `bm_` in `buildTagging`), OR make the handler strip a
   leading `bm_`. Do NOT paper over it in the aggregation query.

2. **Nextflow post-run tag uses `workflow_id = run_id`, not the real workflow id.**
   `_tag_s3_outputs` sets `{"Key":"workflow_id","Value":run_id}`
   (`nextflow_executor.py:3790`) — so the handler's `workflow_id`
   (`s3_event_handler.py:114`) is actually the run UUID. Attribution to *user* is
   fine; per-*workflow* storage rollups will be keyed by run, not workflow. Note
   it if anyone builds per-workflow storage reports.

3. **`_tag_s3_outputs` only tags the `outdir` prefix, run once post-run.**
   It walks `run_meta["outdir"]` (`nextflow_executor.py:3775,3782`) — i.e.
   `nextflow/outputs/{user}/{run}` — and NOT the `nextflow/work/{user}/{run}`
   workdir (`nextflow_executor.py:2742`). Work-dir objects therefore have **no
   tag** and rely entirely on the **key-path** fallback
   (`s3_event_handler.py:100-102`, which does handle `nextflow/work/{user}/…`).
   That fallback works, so work-dir storage IS attributed — but only because the
   path parser covers it. If the workdir prefix ever changes, tagging won't save
   you. Also: objects created *before* the post-run tagging pass fire their
   `ObjectCreated` event **untagged**, so at PUT time attribution is path-based;
   tags only help later `HeadObject`/re-scan. For `biomate-nextflow-work` this is
   fine (paths are per-user); for any bucket whose keys are NOT per-user, the PUT
   would be dropped with "No user_id tag or path match"
   (`s3_event_handler.py:123`).

4. **Deletes reduce cost only if the delete event is attributable.**
   `ObjectRemoved` events carry no object (it's gone), so tags can't be fetched —
   attribution is **path-only** (`_user_id_from_key`, `s3_event_handler.py:85`).
   For the two per-user-prefixed buckets this is fine. A delete of an object
   whose key isn't per-user-prefixed is silently skipped
   (`s3_event_handler.py:122-124`) — the storage ledger won't decrement.

5. **Region/name drift (repeated for emphasis).** If functions were created via
   `make` (bare names, `us-east-1`) but you wire events in `us-west-2` against
   `...-handler` names, the mapping/target/permission will point at
   non-existent ARNs and nothing errors loudly — events just never invoke.
   Confirm live names+region (§0 name-mismatch box) before wiring.

6. **`storage: $0` root cause recap.** Before this runbook, only
   `biomate-nextflow-work` had *any* notification (via the old script), and even
   that depended on the SQS→Lambda mapping actually existing. The uploads bucket
   (`biomate-production`) had **none**, so all direct-upload storage was invisible
   to billing. Wiring both buckets (§A / §B) is the fix.
