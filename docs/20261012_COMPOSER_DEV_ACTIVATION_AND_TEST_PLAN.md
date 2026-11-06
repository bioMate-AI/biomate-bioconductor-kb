# Composer (multi-task DAG) — dev activation + controlled test plan

**Date:** 2026-10-12
**Deployed:** dev is healthy at `bdeaee36` (`result=healthy`, smoke passed). The composer is present
but **flag-gated OFF** (`BIOMATE_MULTITASK_DAG_ENABLED` unset) → zero live-behaviour change today.
**Backs:** reconciliation #3 slices 1–5 (`dd97a65d5`→`bdeaee363`); 18 `decomposed_dag` + related tests.

## 0. What the flag turns on (and the safety envelope)
When `BIOMATE_MULTITASK_DAG_ENABLED=true`, a request that the multi-task classifier splits into N
tasks is assembled into an **executable DAG plan** instead of collapsing to one workflow, and returned
as a whole-plan **chain card** (draft). Key safety facts:
- Generating the card **does not launch anything** — the user must click **Confirm & Run** to dispatch
  (verified: no auto-launch on generation). So **Test 1 below costs $0 of Batch.**
- The path is **fail-safe**: if any task doesn't resolve at medium+ confidence, or a dependent
  handoff has no type match, it **falls back to single-task generation** (never a fabricated plan).
- OFF everywhere else → no other behaviour changes.

## 1. Activation (ops action — env change on the dev Galaxy container)
Dev env vars are set on the container directly (they are NOT synced by `sync_to_dev.sh`). Enable with:
```
# on the dev EC2 (via the team's SSM/ops access), set the env + reload Galaxy:
docker exec biomate-galaxy-dev bash -lc 'export BIOMATE_MULTITASK_DAG_ENABLED=true'   # if using a persisted env file, add it there
# then recreate/reload the container so the env is live, e.g.:
#   docker exec biomate-galaxy-dev printenv BIOMATE_MULTITASK_DAG_ENABLED   # expect: true
#   kill -HUP $(pgrep -f 'gunicorn.*8081' | head -1)                        # reload workers
```
> This is a deliberate ops step (not done by this session — modifying dev out-of-band is against the
> read-only-SSM discipline). Confirm `printenv BIOMATE_MULTITASK_DAG_ENABLED` returns `true` before testing.

## 2. Test 1 — draft generation (ZERO Batch cost) — RUN THIS FIRST
Proves decompose → confidence-gated resolve → validated DAG assembly → typed handoff → input binding
→ pipeline card, **without dispatching any job.**
- **Harness:** `frontend/e2e/composer-dag-draft.e2e.ts` (canonical fixture, single login, no register,
  `BIOMATE_URL=https://dev-public.biomate.ai`). Run:
  ```
  cd frontend && BIOMATE_URL=https://dev-public.biomate.ai E2E_FIXTURE_PASSWORD=... \
    npx playwright test e2e/composer-dag-draft.e2e.ts --reporter=list
  ```
- **Test queries** (decomposable into capabilities that have real workflows):
  - *Fan-out:* "Run QC, read trimming, and adapter screening on my FASTQ in parallel, then summarize."
  - *Sequential:* "Run quality control, then alignment, then differential expression on my RNA-seq data."
- **Assertions (the harness checks):** the final response carries a workflow with
  `workflow_type == 'pipeline'` and `execution_mode == 'dag'`; `pipeline_steps.length >= 2`; each step
  has a `nextflow_path` and a `depends_on` array; for the sequential case at least one
  non-empty `connections` entry; the plan is NOT auto-submitted (no run id).
- **Acceptable negative:** if the classifier/ resolver can't confidently decompose+resolve the query,
  the response is a normal single-workflow card — that's the safe fallback, not a failure. The harness
  distinguishes "DAG card produced" (pass) from "fell back" (skip/log), so a fallback does not red the run.

## 3. Test 2 — bounded live dispatch (COSTS Batch — explicit opt-in only)
Only after Test 1 passes and you accept the spend.
- **Scope guardrail:** a **2-step fan-out of CPU-only, fast workflows** over a **small** input
  (e.g. two lightweight QC/summary workflows on a tiny FASTQ/CSV). No GPU, no large genomes. Expected
  cost ~a few cents, minutes.
- **Steps:** enable flag → send the fan-out query → review the whole-plan card → **Confirm & Run** →
  watch Run Manager: both roots should enter AWS Batch **in parallel**, complete, and publish outputs.
- **Verify:** both child runs `succeeded`; two output artifacts present; chat + Run Manager agree;
  no duplicate jobs; the plan is marked complete only when both children succeed (codex's partial/blocked
  handling covers failures).
- **Do NOT** run an expensive/GPU fan-out as the first live test.

## 4. Verification checklist
- [ ] `printenv BIOMATE_MULTITASK_DAG_ENABLED` → `true` on `biomate-galaxy-dev`.
- [ ] Test 1: DAG pipeline card rendered (whole-plan approval), correct step count + depends_on, no auto-launch.
- [ ] Single-task requests still behave exactly as before (regression spot-check: one ordinary ADMET/RNA-seq request → normal single-workflow card).
- [ ] (If Test 2) parallel Batch dispatch + completion + outputs + chat/Run-Manager agreement.

## 5. Rollback (instant, safe)
```
# unset the env (or set to false) on biomate-galaxy-dev, then reload:
docker exec biomate-galaxy-dev bash -lc 'unset BIOMATE_MULTITASK_DAG_ENABLED'   # or set =false in the env file
kill -HUP $(pgrep -f 'gunicorn.*8081' | head -1)
```
With the flag off, `_handle_multi_task_clarification` is byte-for-byte the prior single-task path.

## 6. Known limits (honest)
- Per-task resolution is a conservative top-match confidence gate (medium bar, score ≥ 6); it won't
  resolve niche/ambiguous tasks → those requests fall back to single-task. Richer resolution + input
  binding beyond the primary file are future sub-slices.
- Dependent-step handoffs are wired only on declared input/output **type** compatibility; a sequential
  plan whose steps have no type overlap falls back. (Fan-out — the common case — needs no handoff.)
- The screenshot's bespoke "rank-sum top-5 aggregation" node is NOT part of this; this delivers
  decompose→fan-out/pipeline→execute. An aggregate/select node is a separate future capability.
