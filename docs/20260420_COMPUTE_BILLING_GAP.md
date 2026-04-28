# Compute Billing Gap — EventBridge Rule Not Firing

**Date:** 2026-04-20  
**Status:** RESOLVED — 2026-04-20

**Resolution:** Rule `biomate-batch-job-state-change` verified ENABLED, targeting `biomate-batch-billing` Lambda.
Lambda invocations: 128 on Apr 18, 111 on Apr 20, 0 errors. Pipeline is fully operational.

## Symptom

`GET /api/billing/usage` returns `compute.total_usd = 0` and `compute.jobs = 0` for all users, even after multiple successful AWS Batch workflow completions.

## Root Cause

The `biomate-batch-billing` Lambda is **not being triggered**. Evidence:
- No `billing:batch:*` Redis keys exist
- `billing:last_batch_event_ts` Redis key is `None` (never set)
- LLM billing works correctly (goes via Galaxy → Redis directly, bypassing Lambda)

The Lambda reads `BIOMATE_USER_ID` from `container.environment` in the EventBridge event. The Nextflow executor correctly injects this env var (lines 1000–1001 in `nextflow_executor.py`). But the Lambda trigger itself is not firing.

## Likely Causes

1. **EventBridge rule not targeting the right Batch queue/CE** — the rule may filter on `biomate-nextflow-queue` but Nextflow also uses sub-queues or the MANAGED CE directly
2. **EventBridge rule disabled** — may have been left inactive after initial testing
3. **Lambda not deployed** — the `.build/` version may not match what's on AWS

## How to Fix

```bash
# 1. Verify EventBridge rule exists and is enabled
aws events list-rules --name-prefix "biomate-batch" --region us-west-2

# 2. Check if the rule targets the Lambda
aws events list-targets-by-rule --rule biomate-batch-billing --region us-west-2

# 3. Enable the rule if disabled
aws events enable-rule --name biomate-batch-billing --region us-west-2

# 4. Test by manually triggering with a fake event
aws lambda invoke \
  --function-name biomate-batch-billing \
  --payload file://test_event.json \
  /tmp/response.json --region us-west-2
```

Test event (`test_event.json`):
```json
{
  "source": "aws.batch",
  "detail-type": "Batch Job State Change",
  "detail": {
    "jobId": "test-job-123",
    "status": "SUCCEEDED",
    "startedAt": 1713600000000,
    "stoppedAt": 1713600300000,
    "container": {
      "vcpus": 4,
      "memory": 8192,
      "environment": [
        {"name": "BIOMATE_USER_ID", "value": "9a2978f9-731d-4e4b-b77b-5f6ccbac5aa4"},
        {"name": "BIOMATE_RUN_ID", "value": "test-run-uuid"}
      ],
      "resourceRequirements": []
    },
    "tags": {"instance_type": "m5.xlarge"}
  }
}
```

## Current Workaround

E2E tests warn (not fail) when `compute_cost_usd = 0`. The compute billing gap does not block any features — it only affects the billing dashboard and ROI reporting.

## Files

| File | Role |
|------|------|
| `backend/lib/galaxy/ai/billing/lambda/batch_event_handler.py` | Lambda handler |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py:1000` | BIOMATE_USER_ID injection |
| `frontend/server/routes.ts:9752` | Billing proxy to Galaxy |
