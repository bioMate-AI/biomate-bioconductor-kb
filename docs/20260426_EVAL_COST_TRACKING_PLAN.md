# Evaluation Cost & Time Tracking — Implementation Plan

**Date:** 2026-04-26  
**Status:** In progress

---

## Problem

Evaluation runs capture wall-clock `latency_sec` per task but record zero cost/token data.
Production chat is fully instrumented (tokens → Lago), but eval runners bypass billing.
Result: no ability to compute per-benchmark cost, compare cost-efficiency vs. published systems,
or audit Lago for eval spend.

---

## Audit Findings

| Layer | Current State | Gap |
|-------|--------------|-----|
| `BenchmarkResult` dataclass | `latency_sec` only | No `input_tokens`, `output_tokens`, `cost_usd`, `model` |
| `results` SQLite table | Same schema | Same 4 columns absent from all eval DBs |
| SSE `final` event | Workflow/state metadata | Token counts not sent to client |
| `BioMateEvalClient.ask()` | Extracts text + run_id | Doesn't read token metadata |
| Lago emission in routes.ts | `if (req.user && !isPilotUser)` | Eval user skipped by this guard |
| `cost_calculator.py` | Has `claude-sonnet-4-5-20250929` | `claude-sonnet-4-6` falls to `default` |
| `duration_ms` in routes.ts | Hardcoded `0` | No actual timing recorded in Lago |

---

## Changes (7 files)

### 1. `backend/lib/galaxy/ai/billing/core/cost_calculator.py`
- Add `"claude-sonnet-4-6": {"input_per_1m": 3.00, "output_per_1m": 15.00}` to `LLM_PRICING`

### 2. `frontend/server/routes.ts`
- Record `streamStartTime = Date.now()` before the Galaxy call
- Add to `responsePayload.metadata`: `input_tokens`, `output_tokens`, `cost_usd`, `model`, `duration_ms`  
  (token counts already computed just above for Lago emission — reuse them)
- Fix `duration_ms: 0` → `duration_ms: Date.now() - streamStartTime`

### 3. `evaluation/core/base_adapter.py`  ✅ DONE
- Added 4 optional fields to `BenchmarkResult`: `input_tokens`, `output_tokens`, `cost_usd`, `model`

### 4. `evaluation/core/results_store.py`  ✅ DONE
- Added 4 columns to `CREATE TABLE results` DDL
- Added `ALTER TABLE` migration loop for existing DBs (idempotent)
- Updated `save_one`, `save`, `load` to read/write the new columns
- Will add `cost_summary()` method returning per-benchmark `total_cost_usd`, `mean_cost_per_task`, `total_tokens`, `mean_latency_sec`

### 5. `evaluation/core/biomate_client.py` — token extraction
- In `ask()`: read `metadata.input_tokens`, `metadata.output_tokens`, `metadata.model` from `final` SSE event
- Compute `cost_usd` locally using same pricing table as `cost_calculator.py`
- Populate `ChatResponse` with these fields (already has `cost_usd` stub at line 44)

### 6. `evaluation/core/biomate_client.py` — Lago emission
- Add `_emit_eval_cost_to_lago(input_tokens, output_tokens, model, duration_ms)` method
- Calls `POST /internal/billing/llm_cost` directly with `X-Internal-Key`
- Uses `EVAL_LAGO_USER_ID` env var (default: `"eval_internal"`) — bypasses `!isPilotUser` guard
- Called after every successful `ask()` call; errors logged but not raised

### 7. `evaluation/core/results_store.py` — cost_summary()
- Add method returning: `total_cost_usd`, `mean_cost_usd`, `total_input_tokens`, `total_output_tokens`, `mean_latency_sec`, `n` per benchmark run
- Used by xlsx generator and runners for cost-per-run reporting

---

## Published Benchmark Cost Data (for matrix comparison)

To be added as "Cost Analysis" sheet in the evaluation matrix xlsx:

| System | Benchmark | Cost/task (est.) | Source |
|--------|-----------|-----------------|--------|
| GPT-4o | BiomniEval1 | ~$0.005–0.02 | OpenAI pricing + ~2K avg tokens |
| Claude 3.5 Sonnet | LABBench CloningScenarios | ~$0.03–0.08 | Anthropic pricing + long cloning context |
| Claude 3.5 Sonnet | LABBench LitQA2 | ~$0.01–0.03 | Anthropic pricing |
| Biomni (paper) | BiomniEval1 | ~$0.02–0.05 | Biomni paper supplementary |
| GPT-4o | SGI-Bench deep_research | ~$0.10–0.50 | Guo et al. SGI-Bench paper |
| GPT-4o | BixBench MCQ | ~$0.01–0.03 | MCQ short context |
| **BioMate** | All | **TBD from Lago** | This implementation |

---

## Lago Customer for Evals

- Customer ID: `eval_internal` (created in Lago if absent)
- Env var: `EVAL_LAGO_USER_ID` (default `eval_internal`)
- All eval LLM calls attributed to this customer → searchable in Lago dashboard
- Separate from production user billing

---

## Deliverables

1. All 7 file changes implemented and verified
2. Existing eval DBs auto-migrated on next run (migration is idempotent)
3. `results_store.cost_summary()` available for all runners
4. `evaluation/scripts/backfill_costs.py` — estimates cost for historical runs using token-count proxy from `agent_response` length (cannot be exact without re-running, but provides order-of-magnitude)
5. "Cost Analysis" sheet added to benchmark matrix xlsx (v14)

---

## Open Questions

- **Eval user in Lago**: does `eval_internal` need a subscription to accept events? → Will test; if needed, create a `free_tier` subscription programmatically.
- **Backfill accuracy**: existing results have no token counts. Backfill will estimate via `len(agent_response) / 4` (chars → tokens proxy). Label clearly as estimates.
- **Screen_gene / autoloop tasks**: some tasks call the agent multiple times (multi-turn, retry loops). Cost per task = sum of all turns. The `ask()` wrapper handles single-turn; multi-turn adapters will need to accumulate across turns.
