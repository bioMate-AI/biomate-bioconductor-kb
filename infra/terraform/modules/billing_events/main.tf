# modules/billing_events
#
# Event *wiring* for the two BioMate billing Lambdas. The Lambda *code* is
# deployed separately by the Makefile / deploy_*.sh scripts under
# backend/lib/galaxy/ai/billing/lambda|infrastructure/ — this module wires the
# EVENTS that trigger them, which today are configured by hand and therefore
# drift / silently break (live billing shows storage:$0 because the S3→SQS→Lambda
# path was never wired).
#
# What this module creates:
#   S3 metering path (per bucket):
#     aws_sqs_queue.s3_events (+ DLQ)          — buffer S3 notifications
#     aws_sqs_queue_policy                     — let S3 SendMessage to the queue
#     aws_s3_bucket_notification               — ObjectCreated:* / ObjectRemoved:*
#     aws_lambda_event_source_mapping          — SQS → biomate-s3-billing Lambda
#   Batch metering path:
#     aws_cloudwatch_event_rule.batch_state    — source aws.batch, "Batch Job State Change"
#     aws_cloudwatch_event_target              — rule → biomate-batch-billing Lambda
#     aws_lambda_permission.allow_eventbridge  — let EventBridge InvokeFunction
#
# What this module does NOT create (owned elsewhere — pass their ARNs/names in):
#   - the Lambda functions themselves  (Makefile: `make s3` / `make batch`)
#   - IAM execution roles              (deploy_s3_lambda.sh / deploy_batch_lambda.sh)
#   - the S3 buckets                   (created outside TF; imported by env if ever)
#   - the ElastiCache Redis / Secrets  (billing-shared, referenced by function env)
#
# Evidence for every name below is cited inline as file:line so nothing is guessed.
# See docs/20260804_BILLING_LAMBDA_WIRING_RUNBOOK.md for the manual-CLI equivalent
# + verification + attribution gotchas.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "env" {
  type        = string
  description = "Environment name (dev/test/stage/prod) — used in tags only; the Lambda/queue names are fixed org-wide to match the existing hand-wired resources."
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
  # The deploy scripts default to us-west-2 (deploy_s3_lambda.sh:7,
  # deploy_batch_lambda.sh:7) and secrets.py:13 also defaults SM region to
  # us-west-2. NOTE the lambda/Makefile:14 default of us-east-1 is a STALE
  # default that does NOT match where the functions actually run — the runbook
  # calls this out. Everything real is us-west-2 (see infra/terraform/envs/*/main.tf:27).
  description = "Region the billing Lambdas + buckets live in."
}

variable "account_id" {
  type    = string
  default = "399683337364"
  # From infra/terraform/envs/test/secrets_access.tf:32-33 (existing ARNs).
  description = "AWS account ID that owns the buckets / functions."
}

# --- Lambda function names (match the deploy scripts, NOT the Makefile) -----
# The Makefile (backend/lib/galaxy/ai/billing/lambda/Makefile:24-25) names the
# functions `biomate-batch-billing` / `biomate-s3-billing`, but the deploy_*.sh
# scripts (which additionally wire the events) create them as
# `biomate-batch-billing-handler` / `biomate-s3-billing-handler`
# (deploy_batch_lambda.sh:9, deploy_s3_lambda.sh:10) and the checked-in
# eventbridge_rules.json:18 targets `...-handler`. The `-handler` names are the
# ones the manual wiring actually uses, so they are the default here. Override
# per env if your deployed functions use the bare Makefile names.

variable "s3_lambda_function_name" {
  type        = string
  default     = "biomate-s3-billing-handler" # deploy_s3_lambda.sh:10
  description = "Name of the deployed S3 storage-metering Lambda."
}

variable "batch_lambda_function_name" {
  type        = string
  default     = "biomate-batch-billing-handler" # deploy_batch_lambda.sh:9
  description = "Name of the deployed Batch compute-metering Lambda."
}

# --- S3 buckets to meter ----------------------------------------------------
# TWO buckets carry billable objects and BOTH must be wired:
#   1. biomate-nextflow-work  — Nextflow outputs + workdir. Keys:
#        nextflow/outputs/{user_id}/{run_id}/...  (nextflow_executor.py:1207,4636,4741)
#        nextflow/work/{user_id}/{run_id}/...     (nextflow_executor.py:2742,4640,5013)
#      Default bucket literal appears throughout nextflow_executor.py
#      (e.g. :2418, :4629, :4734, :9521) and in deploy_s3_lambda.sh:9.
#   2. the app uploads bucket (env S3_BUCKET_NAME; .env.example:40 = biomate-production).
#      Keys: users/{user_id}/uploads/... (frontend/server/s3-client.ts:148,203).
#      The OLD deploy_s3_lambda.sh only wired bucket #1 — that is why direct
#      user uploads were never metered. Wire BOTH.

variable "metered_buckets" {
  type = map(object({
    bucket_name = string
  }))
  default = {
    nextflow_work = { bucket_name = "biomate-nextflow-work" } # deploy_s3_lambda.sh:9
    app_uploads   = { bucket_name = "biomate-production" }    # .env.example:40 (S3_BUCKET_NAME)
  }
  description = "S3 buckets to meter, keyed by a short logical name. The handler resolves user_id from object tag `user_id` then the key path (s3_event_handler.py:16-25)."
}

variable "sqs_queue_name" {
  type        = string
  default     = "biomate-s3-billing-events" # deploy_s3_lambda.sh:12
  description = "SQS queue that fans S3 notifications into the S3 Lambda."
}

variable "sqs_dlq_name" {
  type        = string
  default     = "biomate-s3-billing-events-dlq" # deploy_s3_lambda.sh:13
  description = "Dead-letter queue for the S3 metering queue (maxReceiveCount 3)."
}

variable "eventbridge_rule_name" {
  type        = string
  default     = "biomate-batch-job-state-change" # deploy_batch_lambda.sh:11, eventbridge_rules.json:6
  description = "EventBridge rule capturing Batch job state changes."
}

variable "batch_statuses" {
  type        = list(string)
  default     = ["RUNNING", "SUCCEEDED", "FAILED"] # batch_event_handler.py:249,253; eventbridge_rules.json:12
  description = "Batch job statuses the handler acts on (RUNNING records start, SUCCEEDED/FAILED record completion)."
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  common_tags = {
    Env       = var.env
    ManagedBy = "terraform"
    Project   = "biomate-cicd-rebuild"
    Component = "billing-events"
  }

  s3_lambda_arn    = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.s3_lambda_function_name}"
  batch_lambda_arn = "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.batch_lambda_function_name}"
  sqs_arn          = "arn:aws:sqs:${var.aws_region}:${var.account_id}:${var.sqs_queue_name}"
}

# ===========================================================================
# S3 metering path:  S3 bucket(s) → SQS → Lambda
# ===========================================================================

# --- Dead-letter queue ------------------------------------------------------
resource "aws_sqs_queue" "s3_events_dlq" {
  name = var.sqs_dlq_name
  tags = merge(local.common_tags, { Name = var.sqs_dlq_name })
}

# --- Main queue (with redrive to DLQ, maxReceiveCount 3) ---------------------
# Matches deploy_s3_lambda.sh:82-89.
resource "aws_sqs_queue" "s3_events" {
  name = var.sqs_queue_name

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.s3_events_dlq.arn
    maxReceiveCount     = 3
  })

  # SQS default visibility timeout must be >= the Lambda timeout (30s per
  # deploy_s3_lambda.sh:146 / Makefile). 60s gives margin for retries.
  visibility_timeout_seconds = 60

  tags = merge(local.common_tags, { Name = var.sqs_queue_name })
}

# --- Queue policy: let each metered bucket SendMessage to the queue ----------
# Mirrors the inline policy in deploy_s3_lambda.sh:95-100 but for ALL buckets.
resource "aws_sqs_queue_policy" "allow_s3" {
  queue_url = aws_sqs_queue.s3_events.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for k, b in var.metered_buckets : {
        Sid       = "AllowS3-${k}"
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "SQS:SendMessage"
        Resource  = local.sqs_arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = var.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:aws:s3:::${b.bucket_name}" }
        }
      }
    ]
  })
}

# --- Bucket notifications: ObjectCreated:* / ObjectRemoved:* → SQS -----------
# One notification config per bucket. Events match s3_event_handler.py:6-7 and
# the handler's ObjectCreated/ObjectRemoved branches (s3_event_handler.py:126,146).
# depends_on the queue policy so S3 can validate SendMessage at config time.
resource "aws_s3_bucket_notification" "metering" {
  for_each = var.metered_buckets
  bucket   = each.value.bucket_name

  queue {
    queue_arn = aws_sqs_queue.s3_events.arn
    events    = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
  }

  depends_on = [aws_sqs_queue_policy.allow_s3]
}

# --- Event source mapping: SQS → S3 Lambda ----------------------------------
# Matches deploy_s3_lambda.sh:163-167 (batch-size 10).
resource "aws_lambda_event_source_mapping" "s3_sqs" {
  event_source_arn = aws_sqs_queue.s3_events.arn
  function_name    = local.s3_lambda_arn
  batch_size       = 10
  enabled          = true
}

# ===========================================================================
# Batch metering path:  EventBridge rule → Lambda
# ===========================================================================

# --- Rule on the default event bus ------------------------------------------
# Pattern matches batch_event_handler.py:4-6 and eventbridge_rules.json:8-13.
resource "aws_cloudwatch_event_rule" "batch_state" {
  name        = var.eventbridge_rule_name
  description = "Captures AWS Batch job state transitions for BioMate billing"
  state       = "ENABLED"

  event_pattern = jsonencode({
    "source"      = ["aws.batch"]
    "detail-type" = ["Batch Job State Change"]
    "detail"      = { "status" = var.batch_statuses }
  })

  tags = merge(local.common_tags, { Name = var.eventbridge_rule_name })
}

# --- Target: rule → Batch Lambda --------------------------------------------
# Matches deploy_batch_lambda.sh:134-137 (Id=1).
resource "aws_cloudwatch_event_target" "batch_lambda" {
  rule      = aws_cloudwatch_event_rule.batch_state.name
  target_id = "batch-billing-lambda" # eventbridge_rules.json:17
  arn       = local.batch_lambda_arn
}

# --- Permission: let EventBridge invoke the Batch Lambda ---------------------
# Matches deploy_batch_lambda.sh:124-131.
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeBatchEvents" # deploy_batch_lambda.sh:122
  action        = "lambda:InvokeFunction"
  function_name = var.batch_lambda_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.batch_state.arn
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "s3_events_queue_url" { value = aws_sqs_queue.s3_events.id }
output "s3_events_queue_arn" { value = aws_sqs_queue.s3_events.arn }
output "s3_events_dlq_arn" { value = aws_sqs_queue.s3_events_dlq.arn }
output "batch_rule_arn" { value = aws_cloudwatch_event_rule.batch_state.arn }
output "metered_buckets" { value = [for k, b in var.metered_buckets : b.bucket_name] }
