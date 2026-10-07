# BioMate evaluation against the 6 agent-engineering production principles

**Date:** 2026-10-05 · **Basis:** two screenshots (`agent_experiences1/2.png`) — a practitioner's
6-principle checklist for getting agents into production (*what gets an agent live isn't model
strength; it's whether the task stays controllable, tools don't mis-fire, exceptions recover, and cost
is acceptable*). Each principle is scored against the BioMate codebase (worktree HEAD `4b132ad50`) with
`file:line` evidence, and cross-checked against `origin/integration/next-phase` (125 commits a colleague
added, mostly on-prem/deploy hardening). Verdicts verified by reading code, not assumed.

## Scorecard

| # | Principle | Verdict | One-line |
|---|---|---|---|
| 1 | Don't build a universal agent — bounded task + success criteria | ✅ **HAVE** | Enumerated intent taxonomy + deterministic scope guards + cited QC success contracts |
| 2 | Model for understanding, code for constraints | ✅ **HAVE** | Rule-first resource/extraction layers, deterministic run + QC-autoloop state machines, direct read-only data APIs, cheap-model tiering + caches |
| 3 | Strict tool contracts | ⚠️ **PARTIAL** | Typed schemas + CI drift test + timeouts + state-checked retry ✅; **no first-dispatch idempotency, weak authz on `execute`, no param-value validation** ❌ |
| 4 | Layered memory (not full history) | ✅ **HAVE** | Real layering (window + compression ledger + separate task-state store + run-state) + confidence-filtered prefs + incremental-update semantics; robustness caveats |
| 5 | Eval set + online observability | ⚠️ **PARTIAL** | Broad benchmarks + a real content-level execution grader ✅; **no unified production per-layer trace (5d), benchmarks not a CI merge gate (5c)** ❌ |
| 6 | Design failure paths before launch | ⚠️ **PARTIAL→HAVE** | Provider fallback chain, bounded loops, reclaim-only retry ✅; auto-compression-in-loop, destructive-op guardrails, metric-driven rollout weak (next-phase strengthens several) |

**Headline:** BioMate is **strong on the "boundaries + determinism" principles (1, 2) and memory (4)**,
and genuinely good at offline evaluation (real execution grader). The **three concrete, costly gaps**
to fix first are all about **safe tool execution + observability**: (a) no idempotency on compute
dispatch, (b) weak auth/quota on the most expensive endpoint, (c) no unified production per-layer trace.

---

## 1 — Bounded task, not a universal agent — ✅ HAVE

**HAVE:**
- Enumerated intent taxonomy (closed enum) + per-intent capability map: `frontend/server/galaxy-assistant.ts:1373` (`IntentType`), `:1401` `inferActionsFromType()`. Unknown types → LLM-reasoning-only, so the surface is bounded.
- Deterministic last-mile scope guard (EN+ZH regex, applied *after* routing): `frontend/server/execution-intent-guard.ts:11-45` (`prohibitsWorkflowExecution`).
- Single pipeline entry point: `biomate-connector/mcp/tools_manifest.py:93` (`biomate_session`, "primary entry for 90% of requests") → goal→select→prefill→execute→QC→findings.
- **Success criteria per task:** QC contracts `backend/lib/galaxy/jobs/qc_trace_monitor.py:34` `QC_RED_LINES` / `:67` `QC_GOLD_METRICS` (ENCODE4/GATK, non-overridable); pre-dispatch gates `routes.ts:10219` `detectGenerationFailure`, `:10313` `validateWorkflowInputs`; generation oracles `backend/lib/galaxy/ai/verification_layer.py` (`majority_vote`, `grounded_pick`).

**Caveat:** domain breadth is wide (36 domains, 4,200+ workflows) and `frontend/server/orchestrator.ts`
has an `ORCHESTRATOR_MODE=agentic` that deliberately loosens the bounded routing — bounded *by task type*
but ambitious in coverage. **next-phase:** no change.

## 2 — Model for understanding, code for constraints — ✅ HAVE

**HAVE:**
- Rule-first resource resolution: `backend/lib/galaxy/ai/resource_resolver.py:3-9` (Galaxy GALAXY_SLOTS → nf-core labels → LLM → defaults).
- Deterministic run lifecycle + cross-worker state store: `nextflow_executor.py:55/86/109` (RunStateStore), flow "configuring→running→completed" `:5201`.
- QC auto-loop = deterministic evaluate→remediate (rule-based classify, threshold gates, fail-open): `backend/experiments/autoloop_bridge.py:263/306`, gate registry `nextflow_executor.py:554`.
- Direct read-only data APIs (no model guessing): `get_run`/`list_runs`/`query_database`/`resolve_accession` → direct GET/POST (`biomate-connector/mcp/tools_manifest.py:276/338`).
- Fewer/cheaper model calls: intent forced to Gemini Flash (`galaxy-assistant.ts:323/343`), tiered cost-aware router `backend/lib/galaxy/ai/llm_router.py:72-124`, extraction cache keyed by message SHA `:2360-2367`.

**Gaps/caveats:** inline-data extraction is **LLM-first with regex fallback** (`galaxy-assistant.ts:2404/2442`)
— inverse of the ideal rule-first (the deterministic layer exists but runs second). No `routing_cache`
for the intent decision itself (re-run per message; only the extraction sub-step is cached).
**next-phase:** no change.

## 3 — Strict tool contracts — ⚠️ PARTIAL (the top area to harden)

**HAVE:**
- Canonical typed schemas with a CI drift test: `biomate-connector/mcp/tools_manifest.py:46` `ToolSchema` (input_schema with type/required/enum/default; 25 `required`, 11 `enum` blocks); frontend `orchestrator.ts:36`.
- Pervasive explicit timeouts: `biomate_mcp_server.py:57-64` (connect/read tuples, per-call `timeout=`), frontend `AbortSignal.timeout` `galaxy-assistant.ts:2409/3121`.
- State-checked (non-blind) retry: execute route inspects AutoFix lifecycle before honoring a retry (`routes.ts:10238-10258`, 409 if active); MCP returns structured `RATE_LIMITED`/`SERVER_ERROR` instead of blind re-POST (`biomate_mcp_server.py:242-262`); LLM retry typed + bounded backoff.

**GAPS (prioritized — these are the costliest):**
- **3e — No first-dispatch idempotency.** `run_workflow`/`/api/workflows/execute` take no client idempotency key; server mints a fresh `uuid4()` per call with no in-flight dedupe (`nextflow_executor.py:5265`). Two identical submissions each launch **real AWS Batch compute**. The existing fingerprint dedupe only covers *retries of failed runs during AutoFix* (`routes.ts:10231-10310`).
- **3c — Weak authz on the costliest op.** `routes.ts:10194` `app.post("/api/workflows/execute", optionalAuth, …)` — `optionalAuth` proceeds with no user if the token is absent/invalid, and there's **no `checkBillingQuota`**, while cheaper AI-generation/import endpoints enforce both (`:6735`, `:3614`). Per-tool annotations (`destructive_hint` etc.) are advisory, not enforced.
- **3b — Model params not validated against the spec.** The connector merges LLM `params` into the definition without checking types/allowed_values (`biomate_mcp_server.py:284-316`); `params` is `additionalProperties:true`. Strong *workflow-structure* validation exists (`workflow_proposal_validator.py:650`), but *parameter-value* guardrails don't run at dispatch.

**next-phase:** commit `77e0de074` adds `authenticateToken + userId` ownership on cancel/rerun/execute
(partially closes 3c) — but **no** idempotency key, param-value validation, or quota-on-execute was
found on next-phase either. These remain open everywhere.

## 4 — Layered memory, not full history — ✅ HAVE (robustness caveats)

**HAVE:**
- Real layering: recent-window + LLM-summary compression `frontend/server/context-compressor.ts:46-193` (keeps recent N, pre-extracts dataset/attachment UUIDs verbatim), byte-budget windowing `chat-history-selector.ts:74-142`, persisted ledger (`session_compressions`, `session_summary` tables), structured `<session_memory>` block injected instead of raw history `galaxy-assistant.ts:3145-3167`.
- Task state separate from chat: `SessionMemory` store (`active_task`, `key_decisions`, `current_parameters`, `open_questions`) `galaxy-assistant.ts:1600-1760`; run state in `session_workflows` + Redis run-state pub/sub (distinct from chat).
- Long-term prefs, filtered: `user_patterns`/`context_inferences`/`user_domain_profiles` tables; prompt filter `confidence>0.5`, top-5 (`memory-integration.ts:420-428`); trust-boundary filter blocks private notes from model hints (`memory-knowledge-filter.ts:11-20`).
- **Update recognition (the budget-5000→3000 case):** explicit incremental-merge prompt "update what has changed, keep the rest" (`galaxy-assistant.ts:1627-1644`); `current_parameters` dict overwrites the key; preference upsert overwrites value (`memory-repository.ts:133-144`). It's an explicit eval scenario (`evaluation/datasets/memory_benchmark/scenarios.yaml:433/463`).

**Gaps (why not perfect):** update recognition relies on a Gemini-Flash merge + key-equality upsert —
**no deterministic contradiction detector** (a contradiction under a *different* key or in free-text
`key_decisions` can accumulate both). Preference confidence only **increments, never decays**, and
`user_patterns`/`context_inferences` have **no TTL** — stale long-term prefs can outrank fresher signals.
**next-phase:** no change.

## 5 — Eval set + online observability — ⚠️ PARTIAL (strong offline, weak online)

**HAVE:**
- Broad eval suites: ~24 dataset dirs / ~55 runners under `evaluation/` (`param_prefill`, `cross_domain_routing`, `biomni_eval1`, `admet`/TDC, `pbpk`, `boin`, `stability`, `memory_benchmark`, `autofix`, `prereq_recovery`, `license_gating`, `qc_governance`, `ind_gold_standard`, …); versioned results `evaluation/results/*`.
- **Real execution grader (not similarity):** `evaluation/local_trial/execution_grader.py` — L1 terminal success + ≥1 real output; L2 (`--deep`) fetches S3 outputs and validates CONTENT (JSON non-empty, CSV ≥2 rows) + per-workflow correctness contracts. Explicitly "not string similarity and not an LLM."
- Real-problem categories covered: clarification (`IntentClarificationCard`, `_clarificationGate`), hallucination (`hallucination_detector.py`), tool-failure recovery (`autofix_benchmark`, `prereq_recovery`), high-risk (`license_gating`, `qc_governance`, IND); feedback tables `workflow_user_corrections`, `pilot_feedback`.

**GAPS:**
- **5d — No unified production per-layer trace (the headline gap).** The best per-layer audit (`workflow_generation_audit` via `WorkflowAuditService`) covers only the multi-agent `generate_workflow` endpoint, stores **summaries not the actual prompt / retrieved content**, and **never populates `llm_tokens_used`** (defaults 0). The main **chat** turn's tokens are **heuristic estimates** (`routes.ts:6477`, not `usage.input_tokens`), and its SSE tool/latency trace is **streamed to the client, not persisted**. → A Bad Case shows a wrong answer but you **cannot reliably reconstruct which layer failed** (what the model saw, what was retrieved).
- **5c — Benchmarks are not a CI/merge gate.** CI runs unit/boot/smoke only; the eval runners (`evaluation/runners/run_all.py`) exist but no CI job invokes them on prompt/model/retrieval change → "re-evaluate on every change" is a manual discipline, not enforced.

**next-phase:** adds admin log viewers (`efe44ad6b`, `e057b0f71`) — infra log tailing, **not** agent
per-layer tracing; nothing closes 5d or 5c.

## 6 — Design failure paths before launch — ⚠️ PARTIAL→HAVE (moderately covered)

**HAVE:**
- **6a model-unavailable fallback:** cascading provider chain `backend/lib/galaxy/ai/llm_client_fallback_implementation.py:191` (`generate_with_fallback`), wired live `llm_client.py:188-201`; config `config/llm_providers.yml` (Gemini Pro→Flash→Claude→GPT-4o→local Ollama), auto-skips providers whose key is missing; `local_only()` offline short-circuit.
- **6b max-steps:** bounded loops everywhere (`galaxy-assistant.ts:2828` `MAX_TOOL_TURNS=12`; autofix `max_attempts=5`; `chain_planner.py:288` `max_steps=4`; `nextflow_composer.py:240` `MAX_TOOLS=25`).
- **6g bounded + state-aware retry:** `nextflow_executor.py:3039` `maxSpotAttempts=3` — retries **only** on spot reclaim / host termination, NOT real failures (never masks a bug); LLM retry bounded backoff.
- **6d (partial) run-dispatch confirmation:** explicit "Confirm & Run" gate before compute (`galaxy-assistant.ts:5213/8899-8910`); MEDIUM-confidence asks the user to confirm.

**GAPS:**
- **6c — auto-compression not in the live loop.** The summarizer exists but only behind manual `/api/compress-session` (`routes.ts:6689`); the in-loop control is byte-budget windowing + `.slice(-N)`, which can silently drop earlier context on long sessions.
- **6d — destructive-op guardrails incomplete.** `DELETE /api/workflows/runs/:id` (`routes.ts:14905`) had **no auth, no confirmation** in HEAD; execute/cancel/rerun lacked ownership checks. Confirmation is strong for run-dispatch but absent for destructive data ops.
- **6e/6f — no metric-driven rollout.** Feature-flag % rollout exists (`feature-flags.ts`), and cost/latency/run-status are logged (`cost_log.py`, `study_run_logger.py`), but there's **no computed tool-success-rate / task-completion-rate** and **no canary-then-promote/rollback gated on the four metrics**.

**next-phase strengthens item 6 the most:** Group B (`fa3a26a42` OpenAI-compatible agentic tool loop +
graceful degrade to tool-less on 400/422; provider-aware key lookup; removes hard `ANTHROPIC_API_KEY`
requirement) → **6a**; Group F (`77e0de074` auth+ownership on cancel/rerun/execute) → **6d**; Group G
(`3c217504d`/`e057b0f71` admin system dashboard: run stats, LLM probe, drill-down logs) → **6f**; Groups
A/D (on-prem/MinIO + executor fixes) → general robustness. Still open after next-phase: 6c (auto-compress),
destructive-op confirmation, metric-driven canary.

---

## What `integration/next-phase` adds (colleague's 125 commits) — grouped
- **A. On-prem / air-gapped / MinIO** (~60+ commits): every `boto3.client('s3')` that missed the MinIO `S3_ENDPOINT_URL` fixed (autofix, QC trace monitor, readS3Text, presigned URLs), air-gapped package + offline manual. → robustness, item 6.
- **B. LLM-provider compatibility** (highest item-6a value): full agentic tool loop for OpenAI-compatible providers (Qianwen/DeepSeek/vLLM/GPT-4), Anthropic→OpenAI schema conversion, graceful fallback to tool-less streaming; provider-aware keys; removes hard Anthropic-key requirement.
- **C. Billing / PostgreSQL** migration (PG booleans, PG URL in provisioning). → cost infra (6f).
- **D. Executor / compute backend** (skip S3 HeadBucket in Batch; local executor container fix; k8s + Slurm via `NEXTFLOW_EXECUTOR`; zombie-run kill). → 6g/6e.
- **E. CI / deploy** (SSM dev deploy, longer timeouts, GHCR retag, health waits). → rollout infra (6e).
- **F. Security / auth** (`77e0de074` auth+ownership on cancel/rerun/execute; status-endpoint auth; create-admin shell-injection fix). → 3c/6d.
- **G. Admin dashboard / observability** (system dashboard: process health, run stats, LLM probe; drill-down log viewer). → 5d/6f (infra-level, not per-layer agent trace).
- **H. Compliance docs** (SOC 2 Type 2 + HIPAA prep; `20260719_WORKFLOW_RESILIENCE_GAPS.md`). → governance.
- **I. Misc features** (folder upload 50→200 GB adaptive chunking; instrument→resource inventory; owner-transfer UI; FAERS real params; Chinese i18n).

> Also documented on next-phase (not yet fixed): **workflow UI resilience** —
> `docs/20260719_WORKFLOW_RESILIENCE_GAPS.md` notes no durable invocation record / recovery-on-mount, so a
> Batch job survives a server/session break but the UI orphans it (panel stuck "running"). Cross-cutting
> failure-path gap worth prioritizing.

---

## Top gaps to fix (prioritized, actionable)
1. **Compute-dispatch idempotency (3e)** — add a client idempotency key + in-flight dedupe on `/api/workflows/execute` so duplicate identical submissions don't each launch (paid) Batch compute. *Costliest gap for a pay-per-run platform.*
2. **Auth + quota on `execute` (3c)** — switch `optionalAuth`→`authenticateToken` and add `checkBillingQuota` on the compute endpoint (next-phase's `77e0de074` does the auth half; quota still missing). 
3. **Unified production per-layer trace (5d)** — one persisted per-request record joining model input + retrieved content + tool params + per-node latency + **real** token usage (populate `llm_tokens_used`; use `usage.input_tokens` not estimates; persist the SSE trace). Enables "which layer failed" root-causing.
4. **Param-value validation at dispatch (3b)** — `jsonschema`-validate LLM `params` against the workflow spec's types/allowed_values before merge.
5. **Eval suites as a CI gate (5c)** — wire `evaluation/runners/run_*` into CI on prompt/model/retrieval changes (even a subset) so regressions are caught at merge.
6. **Auto-compression in the live loop (6c)** + **destructive-op confirmation/auth (6d)** + **memory staleness: preference-confidence decay / pattern TTL (4e)** + **deterministic contradiction detection (4d)**.
7. **Metric-driven canary (6e/6f)** — compute tool-success-rate + task-completion-rate, and gate feature-flag promotion/rollback on {completion, tool-success, latency, cost} (next-phase's admin dashboard is the data source to build on).
