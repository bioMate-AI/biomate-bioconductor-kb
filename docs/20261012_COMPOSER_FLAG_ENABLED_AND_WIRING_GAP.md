# Composer flag enabled on dev — and the live-path wiring gap it revealed

**Date:** 2026-10-12
**Session outcome:** `BIOMATE_MULTITASK_DAG_ENABLED=true` is now live on `biomate-galaxy-dev`,
but the zero-cost draft test revealed the composer's code path is **not reached by the live
chat/generation flow**. Flag is active; behaviour is unchanged live because the gated code is dead
relative to `generate_workflow_unified`. This doc records what was done, the two sync-script bugs
fixed along the way, the wiring gap, and the proposed fix.

## 1. Flag activation (done, verified)
- Added `BIOMATE_MULTITASK_DAG_ENABLED=true` to dev `/opt/biomate/.env`, then recreated the Galaxy
  container through the sanctioned `BIOMATE_RESYNC_GALAXY_ENV=1 bash scripts/sync_to_dev.sh`
  (health-gated, rollback-protected). Registered the flag (+ `BIOMATE_PATTERN_ROUTER_ENABLED`) as a
  managed var in `deploy/biomate.env.manifest` (commit `4f53a2d5e`) so it is flipped in-band, not ad-hoc.
- **Verified in the RUNNING container** (not just exit code): `printenv BIOMATE_MULTITASK_DAG_ENABLED`
  → `true`; `decomposed_dag.py` present; module imports clean; `DATABASE_URL`/`JWT_SECRET`/
  `GALAXY_API_KEY` preserved across the recreate; container freshly recreated and healthy; sync
  `result=healthy`, smoke passed.

## 2. Two sync-script bugs fixed (commit `389b46870`)
The first resync run printed `[galaxy-env] Done` and `result=healthy` but the container was NOT
recreated (still "Up 19 hours", flag unset) — a **false green**. Root cause in
`resync_galaxy_env()` (`scripts/sync_to_dev.sh`), in code that had **never executed** (the function
always aborted at the first bug):

1. `CLEANUP_FILES="$CLEANUP_FILES $LIVE_ENV"` ran **inside the remote single-quoted ssh block** under
   `set -u`, where `CLEANUP_FILES` (a LOCAL `on_exit` var) is unbound → fatal → aborted **before**
   `docker stop/rm/run`. Fix: a **remote-side** `trap 'rm -f "$LIVE_ENV"' EXIT` (the remote temp file
   is cleaned remotely; this does not clobber the local lock/SNS `on_exit` trap).
2. `-v $GALAXY_DB_HOST_PATH:/app/database` also expanded remotely (unbound under `set -u`) **and**
   duplicated the `/app/database` mount already captured by `$MOUNTS` → "Duplicate mount point" →
   `docker run` fails **after** `docker rm` → **dev Galaxy down**. Fix: conditional `DB_MOUNT` — rely
   on `$MOUNTS` (verified it already has the mount), add an explicit mount only if missing, with the
   path interpolated locally.

Lesson (for the team): a sync that prints `result=healthy` can still have **skipped** a step — the
old (healthy) container passes the health gate. Always verify the *running container* reflects the
change (here: `printenv` the new var), never trust the "Done" line. Matches
`project_dev_backend_deploy_didnt_land` in memory.

## 3. The wiring gap (the real finding)
The composer DAG hook is in `backend/lib/galaxy/ai/ai_assistant.py`:
`route_and_handle` (≈481) → `_looks_like_multi_task` (≈512) → `_handle_multi_task_clarification`
(≈708) → flag-gated `build_dag_plan` + `to_pipeline_card` (≈764-783).

**But `route_and_handle` has zero live callers.** `grep -rn "route_and_handle|_looks_like_multi_task|
_handle_multi_task_clarification"` across `backend/` + `frontend/` returns only the definitions and
`lib/galaxy/ai/tests/test_multi_task_classifier.py`. The live chat/generation endpoint is
`POST /api/ai_assistant/generate_workflow` → **`generate_workflow_unified`** (≈3795,
"unified search-first"), which does not invoke `route_and_handle`, `_looks_like_multi_task`, or
`_handle_multi_task_clarification`. So:
- The entire multi-task clarification feature (not just the DAG slice) is **dormant** in the live path.
- Enabling `BIOMATE_MULTITASK_DAG_ENABLED` is **inert live** — its gate is never reached.
- The zero-cost draft e2e (`composer-dag-draft.e2e.ts`) correctly produced no DAG card (it also
  produced 0 workflow cards for the test phrasing — under investigation whether the "do not launch /
  prepare the plan" wording also suppressed single-task generation via the execution-intent guard;
  secondary to the wiring gap).

This is the "gap is SELECTION/wiring, not the primitive" pattern (memory
`feedback_audit_biomate_capabilities_first`). The composer primitive (`decomposed_dag.py`, 18 tests,
validated against `galaxy.chain.dag.validate_plan`) is solid; it is simply hooked into a method the
live path never calls.

## 4. Proposed fix (next step — careful, flag-gated, into a hot endpoint)
Wire multi-task detection + the composer into `generate_workflow_unified` so the live
`/api/ai_assistant/generate_workflow` path can emit a whole-plan DAG card:
- Early in `generate_workflow_unified`, when `BIOMATE_MULTITASK_DAG_ENABLED` is on and
  `_looks_like_multi_task(request.request_text)` is true, decompose → `build_dag_plan` →
  `to_pipeline_card`, and return the pipeline-card shape the frontend chain card renders.
- Fail-safe: any miss (not multi-task, a task unresolved, a handoff type-mismatch, any exception) →
  continue to the existing unified single-workflow generation (byte-for-byte current behaviour).
- Confirm the frontend renders the returned `workflow` object as a PipelineListView when
  `workflow_type === 'pipeline'` / `execution_mode === 'dag'` — and that `generate_workflow`'s
  response field name matches what the renderer reads (`workflow` vs `workflow_ga`). (Being mapped.)
- Validate: unit test the live-endpoint branch (hermetic, injected resolver); re-run the zero-cost
  draft e2e; only then sync. Do NOT trigger any Batch run.

**Discipline note:** `generate_workflow_unified` is a hot, critical endpoint. The hook must be
additive, flag-gated, and fail-safe — never alter the default single-task path. Review the full
function + frontend render contract before editing (per CLAUDE.md "Review Code Before Testing").

## 5. RESOLUTION (same day) — the composer already works live; the test was self-defeating
Investigating the 0-card result end to end changed the conclusion. **BioMate already has a working,
live, Node-side sequential-pipeline composer** — I do NOT need to wire the backend DAG composer to
make the common case work.

- **Live path (works):** `galaxy-assistant.ts` `analyzeIntent` → `isMultiIntent`/`isSequential` →
  `processMultiIntent` → `processSequentialPipeline` (@5021) → emits a `workflow_type:'pipeline'`
  card the frontend renders (`chat-message.tsx:841` PipelineListView).
- **Proof (live dev, zero cost):** POSTing the bare query *"Run quality control, then read alignment,
  then differential expression on my RNA-seq data."* to dev `POST /api/biomate/chat` logged:
  `Multi-intent detected: 3 intents [workflow_generation ×3] (SEQUENTIAL pipeline)
  domains=[transcriptomics] chain=bulk_rnaseq_de_analysis` → `isMultiIntent:true, intents:3` →
  `[SEQ] Building sequential pipeline: 3 steps`. The composer decomposed + routed + built correctly.
  → **The "too literal / inflexible decomposition" worry is not borne out for the canonical
  sequential case.**
- **Why the e2e got 0 cards (two bugs, neither in the composer):**
  1. The e2e query appended *"Prepare the plan — do not launch any jobs yet"*, which made
     `analyzeIntent` classify the whole message as `general_question`/`isMultiIntent:false` and
     suppress workflow generation. (Dev log for the earlier e2e: `Intent: general_question,
     isMultiIntent:false, intents:1` ×4.) That tail was never needed for cost safety — generating a
     card never dispatches; `Confirm & Run` does, which the test never clicks. **Fixed** (commit
     `31d2d02ec`): dropped the tail.
  2. **The harness does not drive the live chat UI.** After the fix, the e2e still skipped with 0
     cards, and a dev-log check showed the e2e's message **never reached the backend** (only the
     direct API probe did). So the UI-interaction (fixture-cookie auth + composer send + SSE wait) is
     broken and must be repaired against the canonical `allometric-qc-coverage.e2e.ts` pattern. This
     is a test-harness bug, not a product bug.

## 6. Revised, prioritised follow-ups
1. **(product gap) "Plan it, don't run yet" suppresses generation.** `analyzeIntent` tags
   "prepare the plan / do not launch yet" as `general_question`, so it never reaches the
   execution-intent guard that is designed to keep generation as a *draft* when only launch is
   prohibited (reconciliation #1). Fix: recognise draft/"don't-launch-yet" execution requests as
   (draft) `workflow_generation` at classification. Touches the hot `analyzeIntent` path → careful,
   tested change.
2. **(frontend) `runnableWorkflow` allowlist omits `workflow_type==='pipeline'`** (`routes.ts:6374`)
   → pipeline cards scored non-runnable → wrong `responseState`. One-line, reviewed fix.
3. **(test) repair `composer-dag-draft.e2e.ts` UI-drive** so it actually sends the message and
   asserts the live pipeline card renders.
4. **(cleanup) the backend DAG composer is dead code.** Either wire it as the rigorous canonical
   composer (replacing/validating the Node-side `processSequentialPipeline`, which the 2026-10-08
   audit flagged as having 41% broken chain connections) or remove it. Enabling
   `BIOMATE_MULTITASK_DAG_ENABLED` is inert until then — the flag is now live on dev but changes no
   live behaviour.

**Bottom line:** the canonical sequential composition works live today; the flag enablement was the
assigned task and is done (though inert); the real remaining value is (1) the "don't-launch-yet"
classification gap and (4) deciding the backend-vs-Node composer story — both deliberate, tested
changes, not done in this session.

## 7. ALL FOUR FOLLOW-UPS FIXED + VERIFIED ON DEV (2026-10-12, later same day)
Synced at `33643a3e` (`result=healthy`); frontend refinements committed through `9b2a3c2a5`.
Pre-sync: `tsc` clean; `vitest` 1847 passed / 0 failed.

1. **"Plan it, don't run yet" classification — FIXED** (`7f9a576a7`, `galaxy-assistant.ts` analyzeIntent
   prompt). The exact phrasing that previously classified `general_question`/`isMultiIntent:false`
   now classifies `workflow_generation, isMultiIntent:true, intents:3, SEQUENTIAL pipeline,
   chain=bulk_rnaseq_de_analysis` (dev log). **Regression controls pass** (no over-trigger):
   conceptual "what does a low alignment rate mean?" → `troubleshooting`; "help me design an
   experiment…" → `experiment_design` (neither becomes workflow_generation). On-prem
   `localIntentPrompt` intentionally NOT changed (dev uses the cloud prompt) — parity follow-up.
2. **`runnableWorkflow` allowlist — FIXED** (`94059377a`, `routes.ts:6374`). Added
   `workflow_type==='pipeline'` (+ non-empty `pipeline_steps`). Verified: the `/api/chat/stream`
   SSE for the RNA-seq request now returns `state:"workflow_ready"` (was `workflow_failed`).
3. **Composer e2e — FIXED + PASSES** (`e69fa3ea2`, `9b2a3c2a5`). Root causes were in the harness, not
   the product: (a) `waitUntil:"networkidle"` hung the goto (page non-interactive → message never
   sent → 0 cards; the message reaching the backend was confirmed only after the fix); (b)
   `waitForLoadState("load")` never resolves on the dev build and burned the test timeout; (c) the
   assertion only accepted the inline `pipeline-step` shape, but the live system renders this query
   as a curated **chain in the right panel** (`button-run-workflow-panel` + wf-chip). Now
   representation-agnostic. Result: **PASS (2.4m)** — `pipeline-step rows=0, inline cards=0, panel run
   CTA=true` → runnable multi-step DRAFT plan, not dispatched. Screenshot:
   `frontend/e2e/test-results/composer-dag-draft.png` (chat "Analysis plan — review the steps, then
   Confirm & Run" + right panel "Bulk RNA-seq Differential Expression Analysis" with Phases/After-run
   tabs + Confirm & Run).
4. **Backend DAG composer dead code — RESOLVED (marked, not wired/removed)** (`33643a3eb`,
   `ai_assistant.py`). Added a prominent warning docstring on `route_and_handle` stating it + the
   `BIOMATE_MULTITASK_DAG_ENABLED` composer have no live callers and the live path is
   `generate_workflow_unified` + `processSequentialPipeline`. Kept the tested code as a candidate
   future *rigorous* composer rather than deleting it (per the never-delete-without-asking rule); the
   flag stays inert by design until a deliberate wire-or-remove decision.

**Net:** the user-facing multi-step composition flow is correct and now has a passing live e2e; the
classification gap that hid it is fixed with regression controls; the inert flag/dead code is clearly
labelled. Remaining optional: on-prem `localIntentPrompt` parity for rule #1, and the deliberate
backend-vs-Node composer consolidation.

## 8. Coverage gaps closed (follow-up to "tested fully?") — synced `c8a4f0da`
- **#1 generalization + baseline** — 7 live dev classification probes total: original failing phrasing;
  generalization ("set up a variant calling pipeline … do not run it yet" → workflow_generation;
  "draft an ATAC-seq workflow … review before running" → workflow_generation); baseline intact
  ("Run nf-core/rnaseq on my FASTQ" → workflow_generation; "DESeq2 vs edgeR" → result_comparison,
  not over-triggered; conceptual → troubleshooting; design → experiment_design). Bounded + generalizes.
- **#2 now unit-tested** — extracted the allowlist into `server/workflow-runnable.ts`
  (`isRunnableWorkflow`) and pinned every accepted/rejected shape in `workflow-runnable.test.ts`
  (10 tests incl. empty-pipeline_steps → NOT runnable, error/no-success → NOT runnable). routes.ts
  calls the helper (behavior-identical; live SSE re-confirmed `state:workflow_ready` post-extraction).
- **Inline pipeline representation now unit-tested** — `chat-message.pipeline-approval.test.tsx` asserts
  `pipeline-step` rows == `pipeline_steps.length` (both graph modes). The live e2e only exercises the
  panel/chain representation for the RNA-seq query; this pins the inline PipelineListView branch.
- **e2e** re-run: 2/2 PASS (not flaky on these runs). vitest 1857 passed / 0 failed; tsc clean.
- Still open (minor): firefox browser binary not installed locally (chromium-only); on-prem
  `localIntentPrompt` parity.
