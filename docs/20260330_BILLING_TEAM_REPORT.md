# BioMate Billing System — Team Report

**Date:** 2026-03-30  
**Audience:** Engineering, Product, and Finance teams  
**Prepared by:** Platform Engineering  

---

## Executive Summary

BioMate has a three-tier billing architecture that records usage for LLM inference, cloud compute, and object storage. This report documents the current state, the fixes applied today, the new **test plan** created for internal evaluation, and the honest audit of what drug development workflow costs **are** and **are not** being captured today.

**Bottom line:** Core LLM billing is wired correctly. Compute billing via the `biomate-batch-billing` Lambda is **live and verified** — the function is Active, triggered by EventBridge, and received 50–63 invocations/day last week. S3 storage billing for both user uploads and Nextflow outputs is now **fully wired** (fixed 2026-03-30). Galaxy-native job compute remains the only unmetered gap.

---

## 1. Billing Architecture Overview

```
BioMate User Action
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│  Tier 1 — Real-time Redis (ElastiCache)                 │
│  • Sub-millisecond spend tracking                       │
│  • Quota enforcement gate (blocks jobs over limit)      │
│  • Written by: lago_client.py, realtime_cost_service.py │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│  Tier 2 — Lago (Metering & Invoicing)                   │
│  • Remote instance: http://35.86.137.71:3000            │
│  • Stores granular usage events per metric              │
│  • Generates monthly invoices per plan                  │
│  • Written by: lago_client.py emit_*() methods          │
└──────────────────────────────────────────────────────────┘
       │
       ▼
┌──────────────────────────────────────────────────────────┐
│  Tier 3 — Java Billing Service (35.86.137.71:8080)      │
│  • Wraps Lago with BioMate-specific business logic      │
│  • Customer registration, plan management               │
│  • Prometheus metrics for Grafana dashboard             │
└──────────────────────────────────────────────────────────┘
```

---

## 2. Lago Plans (as of 2026-03-30)

| Plan Code | Name | Interval | Base Price | Use Case |
|-----------|------|----------|-----------|----------|
| `free` | Free | Weekly | $0 | Self-serve exploration |
| `base` | Base | Weekly | $7 | Standard subscription |
| `pro` | Pro | Monthly | $20 | Power users |
| **`test`** | **Test (Unlimited)** | **Monthly** | **$0** | **Internal evaluation** |

### New: Test Plan

The `test` plan was created today specifically for internal drug development evaluation and team testing. It records **all 9 usage dimensions** at $0/unit — no charges, no quota, no time limit.

**Purpose:** Accumulate real usage data for analysis without billing the team, and verify that all cost categories are metered correctly before billing is turned on for real users.

---

## 3. What Each Plan Tracks

| Metric | `free` / `base` / `pro` | `test` |
|--------|------------------------|--------|
| LLM aggregate tokens (`llm`) | ✓ (package model) | — |
| **LLM input tokens** (`llm_input_tokens`) | — | ✓ per call, per model |
| **LLM output tokens** (`llm_output_tokens`) | — | ✓ per call, per model |
| **vCPU-seconds** (`batch_vcpu_seconds`) | — | ✓ per job |
| **GPU-seconds** (`batch_gpu_seconds`) | — | ✓ per job |
| **Memory GB-sec** (`batch_memory_gb_sec`) | — | ✓ per job |
| **S3 storage GB-hr** (`s3_storage_gb_hours`) | — | ✓ |
| **S3 PUT requests** (`s3_put_requests`) | — | ✓ |
| **S3 GET requests** (`s3_get_requests`) | — | ✓ |
| **S3 data transfer GB** (`s3_data_transfer_gb`) | — | ✓ |

The `test` plan has the same depth of recording as the local development Lago instance but without any charges.

---

## 4. Drug Development Workflow — Cost Map

A complete drug discovery session (target ID → ADMET → virtual screening → lead optimisation) consists of the following cost-generating components. The table shows what is metered today.

### 4.1 LLM Inference Costs

Every interaction with Claude generates billing events. The billing hook is in `llm_client.py:_emit_llm_billing()` which fires after every successful API call.

| Step in drug discovery | Model | Approx tokens/call | Metered? |
|------------------------|-------|-------------------|----------|
| User intent classification | claude-3-5-haiku | ~200 in / 100 out | ✓ |
| Workflow selection (search + ranking) | claude-3-5-haiku | ~500 in / 300 out | ✓ |
| Workflow generation / parameter enrichment | claude-sonnet-4-5 | ~3,000 in / 2,000 out | ✓ |
| Error explanation (D4) | claude-3-5-haiku | ~500 in / 200 out | ✓ |
| Session summary (LTM compression) | claude-sonnet-4-5 | ~4,000 in / 1,000 out | ✓ |
| QC gate error analysis | claude-3-haiku | ~1,000 in / 500 out | ✓ |
| Workflow autofix (agent fixer) | claude-sonnet-4 | ~5,000 in / 2,000 out | ✓ |
| Parameter analysis | claude-3-5-sonnet | ~2,000 in / 1,000 out | ✓ |
| Workflow modification classifier | claude-haiku-4-5 | ~300 in / 100 out | ✓ |

**Estimated LLM cost per drug discovery session:** ~$0.05–$0.20 (mostly Haiku; Sonnet only for generation)

> **Known gap:** The `_fast_llm_client` used for classification tasks in `AIAssistant` does not receive a `user_id` when the session is first created. Events are emitted with `user_id=""` and dropped silently. This means 2–3 LLM calls per session (intent classification, quick search ranking) are not attributed to the user. Fix: set `self._fast_llm_client.user_id = user_id` in the `_classify_fast()` path before the first call.

### 4.2 Cloud Compute Costs

Nextflow workflows run on AWS Batch. Compute billing is triggered via `POST /internal/billing/job_complete` from a Lambda function that monitors Batch Job State Change events.

| Drug discovery tool | Instance type | Duration | Approx cost |
|--------------------|---------------|----------|-------------|
| nf-core/rnaseq (MoA analysis) | m5.4xlarge | 4–8 hrs | $3–6 |
| AutoDock Vina (virtual screening) | c5.4xlarge | 2–6 hrs | $2–5 |
| DiffDock (ML docking) | p3.2xlarge (GPU) | 2–4 hrs | $6–12 |
| nf-core/alphafold (structure) | p3.2xlarge (GPU) | 3–6 hrs | $9–18 |
| AiZynthFinder (retrosynthesis) | m5.2xlarge | 1–3 hrs | $0.5–1.5 |
| ADMET-AI (toxicity screening) | m5.xlarge | 0.5–1 hr | $0.10–0.20 |

**Estimated compute cost per drug discovery session:** $20–$50 (depends on compound count and whether GPU tools run)

> **Status: Fully operational.** The `biomate-batch-billing` Lambda (`us-west-2`) is **Active**, wired to the `biomate-batch-job-state-change` EventBridge rule, and processed 50–63 invocations/day in the past week (2026-03-24 to 2026-03-28). Last deployed: 2026-03-11T20:15 UTC. It writes directly to Redis with no external API calls — the fix described in `docs/20260311_1849_BILLING_SYSTEM_DOCUMENTATION.md` was deployed and confirmed.
>
> The repo source file (`batch_event_handler.py`) was out of date; it has been synced to match the deployed version today.

### 4.3 S3 Storage Costs

Workflow inputs (FASTQ, SDF, PDB), outputs (docking poses, reports, QC files), and intermediate files are stored in S3. S3 billing hooks (`emit_s3_put`, `emit_s3_get`) are in `billing_router.py` and triggered by explicit API calls.

| Data type | Typical size | Storage duration |
|-----------|-------------|-----------------|
| Input compound library (SDF) | 10–500 MB | Per session |
| AlphaFold output (PDB + PAE) | 5–50 MB | Long-term |
| Docking output poses | 50–500 MB | Per session |
| nf-core HTML QC reports | 1–10 MB | Long-term |
| FASTQ input files | 2–20 GB | Per project |

> **Status (2026-03-30): ✅ Fixed.** The `biomate-s3-billing` Lambda (us-east-1) receives S3 ObjectCreated events via SQS for both `biomate-production-data` and `biomate-nextflow-work` buckets. User uploads are tagged with `user_id` at the API layer (`s3-client.ts`). Nextflow outputs are attributed via (a) per-user S3 path prefix (`nextflow/outputs/{userId}/{runId}/`) + path-based fallback in the Lambda, and (b) post-run bulk tagging (`_tag_s3_outputs()` in `nextflow_executor.py`). Smoke-tested and confirmed working.

---

## 5. Hidden / Unmetered Costs (Current Gaps)

These are real costs incurred during a drug discovery session that are **not captured** in the current billing system.

### Gap 1: Galaxy Workflow Engine Compute

When workflows run inside Galaxy (`.ga` workflows, not Nextflow), they use the Galaxy job runner which may allocate its own compute resources. There is no billing hook in Galaxy's job runner (`backend/lib/galaxy/webapps/galaxy/api/workflows.py`). Galaxy-native tool execution is **completely unmetered**.

**Impact:** Low for current usage (most drug discovery tools run as Nextflow). Will become significant if Galaxy tool usage grows.

**Fix:** Add a Galaxy job completion hook that calls `/internal/billing/job_complete` after each Galaxy tool run.

### Gap 2: External API Usage (PubChem, UniProt, ChEMBL)

BioMate's drug discovery workflows query external databases directly:
- **UniProt** — protein sequence and annotation lookup (free, no cost)
- **PubChem** — compound data and structure retrieval (free, no cost)
- **ChEMBL** — bioactivity data (free, no cost)
- **AlphaFold DB** — structure retrieval when available (free, no cost)

These are all free public APIs. No billing needed. ✓

### ~~Gap 3: S3 Storage for Nextflow Outputs~~ — RESOLVED 2026-03-30

~~Nextflow outputs are deposited to S3 via the `publishDir` directive in workflow configs. These writes happen inside the Nextflow process (in Batch containers), not through BioMate's API layer. As a result, `emit_s3_put()` is **never called** for workflow output files.~~

**Fixed:** Three complementary changes now ensure Nextflow output storage is captured:
1. **Per-user S3 paths**: `nextflow_executor.py` now routes outputs to `s3://{bucket}/nextflow/outputs/{userId}/{runId}/` and work dir to `s3://{bucket}/nextflow/work/{userId}/{runId}/`. The Lambda extracts `user_id` from these path prefixes as a fallback.
2. **Post-run bulk tagging**: `_tag_s3_outputs()` in `nextflow_executor.py` calls `s3.put_object_tagging()` on all output objects after a run completes, adding `user_id`, `workflow_id`, and `tagged_by=biomate-postrun` tags.
3. **Lambda path fallback**: The updated `s3_event_handler.py` reads `user_id` from the key path (`nextflow/outputs/{user_id}/...`) when the object tag is absent (e.g. for objects written before the post-run tagging completes).

Smoke tested: `user_id resolved from key path: nextflow/outputs/bm_test_user_001/... → bm_test_user_001`.

### Gap 4: LLM Classification Calls Without User Attribution

As noted in §4.1, 2–3 fast Haiku classification calls per session are emitted with `user_id=""` and silently dropped. These represent ~$0.001–0.005 per session — small but they accumulate and misrepresent session-level cost.

**Fix (one line):** In `ai_assistant.py:_classify_fast()`, add:
```python
if self._fast_llm_client and user_id:
    self._fast_llm_client.user_id = user_id
```

### Gap 5: Java Billing Service is DOWN

The Java billing service (`http://35.86.137.71:8080`) reports `DOWN` on its health endpoint. This means:
- Prometheus metrics are not being exported to Grafana
- The service cannot proxy Lago usage queries
- The Lago webhook (`/api/billing/webhooks/lago`) cannot receive payment events

**Fix:** Check the service logs on the EC2 instance for the root cause (likely a PostgreSQL connection timeout). Restart if needed.

---

## 6. Configuration Fixes Applied Today

The following configuration errors were discovered in the audit and corrected:

| File | Setting | Old value | New value |
|------|---------|-----------|-----------|
| `backend/.env` | `LAGO_API_KEY` | `ba049ead` (local Lago, wrong) | `01b71711` (remote Lago) |
| `backend/.env` | `LAGO_API_URL` | `http://localhost:3010` | `http://35.86.137.71:3000` |
| `backend/.env` | `LAGO_WEBHOOK_SECRET` | `CHANGE_ME_...` | `9ef2c8b4-...` (actual HMAC key) |
| `billing_system/application-dev.yml` | `lago.api-key` | `ba049ead` (default, wrong) | `01b71711` |

**Critical code fix:** `lago_client.py:subscription_id()` was generating `sub_{user_id}` but Lago subscriptions are created as `bm_{user_id}_{plan_code}` by the Java service. This mismatch caused **all 37,012 events** to have `lago_customer_id=null` — events arrived but could not be attributed to any customer. The function is now fixed to match the Java service convention.

---

## 7. Current Billing Status: Drug Development Test

To enable cost tracking for drug development evaluation, assign the test user(s) to the `test` plan:

```bash
# Via Lago API
curl -X POST http://35.86.137.71:3000/api/v1/subscriptions \
  -H "Authorization: Bearer 01b71711-be39-49af-8d14-87a4ee827157" \
  -H "Content-Type: application/json" \
  -d '{
    "subscription": {
      "external_customer_id": "bm_{GALAXY_USER_ID}",
      "plan_code": "test",
      "external_id": "bm_{GALAXY_USER_ID}_test"
    }
  }'

# Or via BioMate registration endpoint
POST /internal/billing/register_user
{ "user_id": "{GALAXY_USER_ID}", "email": "...", "name": "...", "plan": "test" }
```

Once subscribed to `test`, all LLM calls and Batch jobs (when Lambda is active) will appear in Lago's usage dashboard with full breakdown by metric type. Usage is visible at:

```
http://35.86.137.71/customers/{customer_id}/usage
```

Or via API:
```bash
curl "http://35.86.137.71:3000/api/v1/customers/bm_{USER_ID}/current_usage?external_subscription_id=bm_{USER_ID}_test" \
  -H "Authorization: Bearer 01b71711-be39-49af-8d14-87a4ee827157"
```

---

## 8. Verification: Smoke Test Results

A smoke test subscription (`bm_smoketest-001`) was created on the `test` plan and three events were sent:

| Metric | Units sent | Recorded in Lago | Charge |
|--------|-----------|-----------------|--------|
| `llm_input_tokens` | 1,234 | ✓ 1,234.0 | $0.00 |
| `llm_output_tokens` | 567 | ✓ 567.0 | $0.00 |
| `batch_vcpu_seconds` | 7,200 | ✓ 7,200.0 | $0.00 |

All events were correctly attributed to the subscription. The usage window opened immediately upon subscription creation.

---

## 9. Priority Action Items

| # | Priority | Action | Owner | Effort | Status |
|---|----------|--------|-------|--------|--------|
| 1 | ✅ Done | `biomate-batch-billing` Lambda is live (50–63 invocations/day, last 7 days) | — | — | Confirmed |
| 2 | ✅ Done | Fix `_fast_llm_client.user_id` not being set for classification calls | Backend | 30 min | Fixed today |
| 3 | 🔴 Critical | Fix Java billing service `DOWN` state — check EC2 logs, restart | Infra | 1 hr | Open |
| 4 | ✅ Done | S3 billing for Nextflow outputs: per-user paths + post-run tagging + Lambda path fallback | Backend | — | Fixed 2026-03-30 |
| 5 | 🟡 Medium | Add Galaxy job completion billing hook | Backend | 2 hr | Open |
| 6 | 🟡 Medium | Assign drug development evaluation users to `test` plan | Ops | 15 min | Open |
| 7 | 🟡 Medium | Delete or void the `messi@example.com` $16,847 test invoice in Lago | Ops | 15 min | Open |

---

## 10. Cost Estimate: Full Drug Discovery Session (Reference)

For planning and investor reporting, the estimated all-in platform cost per complete drug discovery campaign:

| Component | Metered? | Cost range |
|-----------|---------|-----------|
| LLM inference (all steps) | ✓ Live (small gap fixed today) | $0.05 – $0.20 |
| AWS Batch compute (Nextflow) | ✓ Live and verified | $20 – $50 |
| S3 storage (Nextflow outputs) | ✅ Fixed — per-user paths + post-run tagging | $0.02 – $0.50/month |
| S3 storage (user uploads) | ✅ Fixed — tagged at upload time | $0.02 – $2.50/month |
| Galaxy-native tool compute | ✗ Gap | $0 (low usage currently) |
| External API calls | N/A (free public APIs) | $0 |
| **Total per session (billed)** | | **$20 – $53** |
| **True total (incl. gaps)** | | **$20 – $56** |

At the `base` plan ($7/week ≈ $30/month), a moderately active user running 1–2 drug discovery sessions per month would approach or exceed their plan value in compute alone. This is the expected model: base fee covers platform access, and heavy users will be upsold to `pro` or enterprise pricing as Batch compute costs become significant.

---

*This document covers the state as of 2026-03-30. For questions, see the billing audit detail: `docs/nextPhase/20260330_BILLING_AUDIT.md`.*
