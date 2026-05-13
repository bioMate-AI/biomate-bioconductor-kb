# Galaxy `dev` Branch Capabilities — Learning Notes + Deep Agent Integration Plan

**Date:** 2026-05-12
**Audience:** BioMate engineers
**Galaxy clone:** `/home/yzhang/biomate/galaxy_nextflow` (branch `origin/dev`, github.com/bioMate-AI/galaxy)
**BioMate target branch:** `integration/next-phase`
**Last updated:** 2026-05-12 (post-session)

---

## Session log (this branch, 2026-05-12)

Five commits ahead of `165885eac` (this session):

| Commit | What landed |
|---|---|
| `4ec1d56b8` | Tier-1/Tier-2 fixers + 3 helpers + 5 ORM models + Alembic `a7f3deepagent` migration. 16 fixers registered, framework operational. |
| `be60cd0e7` | Two upstream-bug fixes in colleague's code: `llm_client.py` default model was `gemini-3-flash-preview` (colleague-local proxy default, returns 404 on real Anthropic API); `agent.py` line 102 referenced `['analysis']` but the prompt asks LLM for `['initial_assessment']`. Should be reported back to colleague. |
| `3ba1be2ef` | New `POST /api/workflows/{id}/deep_diagnose` endpoint in `autofix3.py`. Reads last 400 lines of `.nextflow.log`, runs DeepAnalysisAgent in-process, returns structured diagnosis. |
| `2f869e939` | (Reverted in next commit) Added a "Get a deeper diagnosis" button + result panel into `nextflow-workflow-viewer.tsx`. Wrong UX direction. |
| `<pending>` | Revert the panel; redesign as backend-auto-trigger + chat-progress lines. See "Revised UX design" below. |

**E2E verified during session**: against real `backend/.nextflow.log` (FQ_LINT exit-127 from nf-core/rnaseq), the agent in 7.6s diagnosed `MISSING_TOOL_OR_ENVIRONMENT_ERROR` at confidence 0.98 and recommended `-profile docker` / install fq / fix container config. A second run with multi-round investigation took 27.7s, produced 4 concrete remediation paths, and self-reported low confidence (0.35) when its trace-file lookup returned empty — that's good calibration, not failure.

---

## Revised UX design — chat-progress, no panel (2026-05-12, post-revert)

The opt-in "Get a deeper diagnosis" button was the wrong place to surface DeepAgent. Deep Agent should run **automatically when a workflow fails** and **stream progress into the existing chat** as friendly natural-language updates. No new panel in the workflow viewer — the chat is where the user already looks for AI-driven help.

### Two output channels, one shared agent run

```
[Workflow status flips to 'failed']
    ↓ (auto-trigger, server-side)
[Backend kicks off DeepAnalysisAgent in a background task]
    ↓
[DeepAnalysisAgent emits round-by-round progress callbacks]
    ↓
    ├─► USER CHANNEL — chat-friendly progress lines
    │   Posted as AI-author messages into the current chat session.
    │   Each line is 1 sentence, plain English, scientist-readable.
    │
    │   Example sequence for the FQ_LINT case:
    │     "Looking into why your workflow failed…"
    │     "Reading the Nextflow logs and the failing task's output…"
    │     "Found it — the `fq` tool isn't in the container used by FQ_LINT."
    │     "Easiest fix: re-run with `-profile docker` so the container loads."
    │     "Want me to update the parameters and restart?"
    │
    └─► ENGINEER CHANNEL — structured log + sessions endpoint
        Every round emits a structured log line tagged `[DEEPAGENT]` with:
          invocation_id, round_number, model, tokens_in, tokens_out,
          stop_reason, tool_called, tool_args, tool_result_size,
          elapsed_s, cumulative_cost_usd, current_confidence
        Same data persisted to `ai_fix_audit_log` (table from migration
        a7f3deepagent) and surfaced via existing `/api/autofix3/sessions`.
```

### Why two channels

- **User channel** = end-user clarity. The user shouldn't see "tool=grep round=2 tokens=412" — they should see "I'm checking the config file." The progress lines double as social proof ("the system is actually working on this, not just hanging") during the 8–30s reasoning window.
- **Engineer channel** = BioMate-internal observability. When a diagnosis is bad/wrong, the engineer needs round-by-round data: which tool calls the agent made, what they returned, where the reasoning went off-track. Structured log lines + DB rows make this debuggable without re-running the agent.

### Two intervention points

The user's phrasing was "frontend intervene, backend intervene":

- **Frontend intervene** — at the end of the chat-progress sequence, a final message offers a concrete next action ("Want me to update parameters and restart?"). Click → triggers the existing `WorkflowRestarter` path with the agent's `suggested_params`. The user never opens a separate panel; the entire interaction is in chat.

- **Backend intervene** — an engineer reading `[DEEPAGENT]` log lines (or the `/api/autofix3/sessions` JSON) can see exactly where the agent went wrong, then patch a rule fixer, a prompt, or a tool definition. The structured trace is the intervention point.

### Why this design beats the panel design

| Aspect | Old (panel) | New (chat-progress) |
|---|---|---|
| Discovery | User has to know to click a button | Auto-fires on failure |
| Trust during 8–30s wait | Spinner ("Investigating…") | Live progress lines = real signal |
| Where the diagnosis lives | Buried inside the failure card in the workflow panel | In chat alongside the user's other AI conversation context |
| Path to action | Click button → see card → no clear next step | Final progress line offers a specific action ("Restart with these params?") that hooks directly into existing chat-driven retry flow |
| Engineer observability | Same single JSON response | Round-by-round structured events |

### Implementation plan (pending after revert)

1. **Backend** — `autofix3.py`: convert the synchronous `deep_diagnose` endpoint into a background-runnable function. Add a `progress_callback` param to `DeepAnalysisAgent.analyze()` (in `agent.py`) so each round can emit `{round, phase, friendly_message, technical_payload}`.
2. **Backend** — Auto-trigger: wire into the Nextflow failure path in `nextflow_executor.py` so any state transition to `failed`/`error` kicks off deep diagnose for that invocation_id.
3. **Backend** — User channel sink: friendly messages are persisted into the chat-history DB associated with the failed invocation's `chat_session_id` (the same session that initiated the workflow). Frontend chat-stream picks them up automatically via the existing SSE.
4. **Backend** — Engineer channel sink: structured payloads emitted via `log.info("[DEEPAGENT][inv=%s] round=%d ...", ...)` and persisted as `AIFixAuditLog` rows (one per round).
5. **Backend** — Final action message: when the agent completes, post a chat message containing the suggested fix + a structured action hint (`{action: 'restart_with_params', params: {...}}`) that the existing chat UI can render as a clickable button (similar to the existing `chat_prompt` "Fix & Retry via Chat" pattern).
6. **Test** — End-to-end against real `.nextflow.log` files. Verify both channels fire correctly. No dev sync until E2E passes locally.

### What stays from prior work

- The Galaxy backend endpoint `POST /api/workflows/{id}/deep_diagnose` stays (becomes the synchronous fallback / explicit-trigger path for the engineer channel).
- The Node.js proxy in `routes.ts` stays (still useful; same path).
- The `_resolve_workflow_dir`, exit-code regex, task-name extraction logic stays.
- All Tier-1/Tier-2 fixers stay.
- ORM models + migration stay (the engineer-channel sink lands in `ai_fix_audit_log`).

### What gets reverted (next commit)

- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — the panel UI (button + result card + state). Diff: −94 lines.

---

## TL;DR

The colleague's Galaxy `dev` branch has been pushing significant AutoFix and infra work since the last integration. The **good news**: the core Deep Agent framework (`agent.py`, `toolkit_v2.py`, `iterative_debugger.py`, `autofix3_orchestrator.py`) is **already byte-identical** between the two repos — likely from the earlier integration round. What's missing in BioMate is a layer of **new fixer plugins** that hook into that framework, plus a few helpers and one API endpoint. Estimated integration effort: **~2 days of focused work, not weeks.**

Four other capabilities (timing logger, compatibility checker, Prometheus stack, optimized Docker images) are also new on Galaxy `dev` — value-ranked and triaged below.

---

## Part 1 — What each piece does (learning notes)

### A. The AutoFix architecture, end-to-end

The Galaxy AutoFix system is a **multi-tier closed-loop workflow repair system**. When a Nextflow workflow fails on AWS Batch, AutoFix:

1. Extracts the error logs from the workflow's work directory (`nextflow.out`, `workflow-trace.txt`, task `.command.log`).
2. Runs a chain of **Fixers** in priority order. Each Fixer inspects the error and decides if it can fix it; the chain stops on the first success.
3. Applies the fix (parameter update, file edit, container swap, etc.) and **restarts the workflow** via the Galaxy `queue_invoke` API (or BioMate's Nextflow executor).
4. Records the attempt for learning and audit.

There are two generations layered together in galaxy `dev`:

#### **AutoFix v1 — Rule-based Fixers** (`orchestrator.py`)

The original system. `AutoFixOrchestrator` runs N rule-based `BaseAutoFixer` subclasses sequentially. Each fixer pattern-matches against the error log and proposes a `FixPlan` consisting of typed `FixAction`s (e.g., `PARAMETER_UPDATE`, `RETRY`, `FILE_EDIT`).

**Existing fixers in BioMate today** (8): AWS resource, file format, container error, retry strategy, data file, Nextflow parameter, reference genome, samplesheet, plus one LLM-first variant.

Each fixer's lifecycle:
```
detect_issues() → generate_fix_plan() → evaluate_risk() →
[user approval if risk≥medium] → capture_state() → apply_fix() →
[rollback() if validation fails]
```

The `FixContext` carries `user_id`, `invocation_id`, budget caps, and user preferences. Audit logs persist to `AIFixAuditLog` (a Galaxy DB model BioMate would need to either port or stub).

#### **AutoFix v3 — Deep Agent + Iterative Loop** (`autofix3_orchestrator.py`)

The new layer. Three composing pieces:

- **`DeepAnalysisAgent`** (`agent.py`) — A multi-round Claude-driven investigator. It receives the error log, decides whether deep investigation is needed, then uses a tool-use loop (Anthropic Tool Use API) to call filesystem and shell tools to read the workflow files, grep configs, inspect trace files, and finally returns a structured diagnosis:
  ```json
  {
    "error_category": "STAR_INTRON_TOO_SHORT",
    "root_cause": "STAR aligner alignIntronMax=300000 is too small for this genome",
    "fixable": true,
    "suggested_params": {"star_alignIntronMax": 500000},
    "investigation_steps": [...],
    "confidence": 0.92
  }
  ```
  Max 5 rounds of reasoning. Pure logic, no Galaxy dependency.

- **`EnhancedToolKit`** (`toolkit_v2.py`) — The tool sandbox. Exposes ten tools to the LLM via Anthropic Tool Use schema:
  `read_file`, `edit_file`, `write_file`, `bash_command`, `glob`, `grep`, `s3_download`, `s3_upload`, `inspect_trace`, `get_workflow_params`.
  Safety guarantees: file ops restricted to workflow_dir + Galaxy root; bash whitelisted (`ls`, `grep`, `wc`, `head`, `tail`, `cat`, `find`, `file`, `stat`, plus `aws`, `python`, `nextflow`, `docker`); no redirection or pipes; 30s timeout; 10MB file cap; .env/credentials blacklisted.

- **`IterativeDebugger`** (`iterative_debugger.py`) — The outer loop. Calls `DeepAnalysisAgent.analyze()`, applies the suggested fix, re-runs the workflow step, hashes the new error, and decides whether to continue. Five termination conditions: `success`, `max_attempts`, `duplicate_failures` (same error_hash twice), `no_progress` (progress score stagnates), `timeout` (default 300s). Returns a `DebugSession` with full attempt history.

#### **The integration glue: `EnhancedAutoFix`** (`enhanced_autofix.py`)

Wraps the v1 orchestrator and adds:
1. **Tool error pattern matching** — known signatures lookup
2. **Few-shot examples** — past successful fixes injected into LLM prompts (in-memory, session-scoped — not yet persistent)
3. **Reference genome detection** (hg38, mm10, etc.) for the `ReferenceGenomeFixer`
4. **File format detection** (Phred+33 vs +64, CRLF) for the `FileFormatFixer`
5. **System prompt enhancement** — domain-aware prompts per pipeline type
6. **Dependency checker** — version compatibility for tools
7. **User guidance generator** — when no fix is auto-applicable, returns a human-readable problem summary + recommendations + doc links

This is the "outer ring" the API endpoints call.

#### **The new fixers in `dev` that BioMate is missing**

These are the heart of what `dev` has been working on. They are **plug-in fixers** that sit alongside the existing rule fixers in the chain:

| Fixer | Size | What it does |
|---|---|---|
| **`deep_agent_fixer.py`** | 23 KB | **The Tier-2 LLM fallback.** Implements the `BaseAutoFixer` contract by delegating to `DeepAnalysisAgent`. Only fires when all rule fixers have failed (last in the chain). Takes the diagnosis JSON and converts it to a standard `FixPlan`. This is the bridge between v1 (rule chain) and v3 (Deep Agent) — without it, the Deep Agent only runs through the `autofix3` orchestrator, not through the main `EnhancedAutoFix` pipeline. |
| **`llm_universal_fixer.py`** | 33 KB | A more aggressive LLM fixer that doesn't require diagnosis structure — handles arbitrary error categories. Uses fewer tools than `deep_agent_fixer` but has broader LLM prompt logic. |
| **`pure_llm_fixer.py`** | 21 KB | "No-rules" approach: passes raw error log + workflow context to Claude and asks for a fix. Used as a baseline / experimental comparison against the hybrid strategy. |
| **`llm_learning_fixer.py`** | 17 KB | Stores past `(error_hash → successful_fix)` pairs and injects them as few-shot examples on future calls. Currently in-memory but designed for DB persistence. **The closest thing to the project's "learning loop" requirement.** |
| **`parameter_validation_fixer.py`** | 19 KB | Validates S3 paths exist (via `head_object`), validates enum values against pipeline schema, checks parameter types. Fixes by either auto-correcting (e.g., snap to allowed enum value) or returning user-guidance. |
| **`cpu_resource_fixer.py`** | 9 KB | Specialized for "this tool needs more CPU" errors (commonly STAR aligner). Bumps `max_cpus` with safety cap at 96. |
| **`docker_daemon_fixer.py`** | 6 KB | Docker daemon errors, image pull failures, container permission errors. |

#### **Supporting helpers BioMate is missing**

| File | Purpose |
|---|---|
| `deep_log_analyzer.py` | Multi-pass log parser: splits Nextflow output into per-task chunks, extracts the actual failing command, isolates the error block. Feeds `DeepAnalysisAgent` cleaner input. |
| `error_log_parser.py` | Lower-level regex parsing of Nextflow trace and log files. Extracts `taskName`, `exit_code`, `error_action`, `submit/start/complete` timestamps. |
| `dataset_validator.py` | Validates dataset existence, format, integrity *before* re-submitting the workflow (avoids burning a Batch cycle on a known-bad input). |

#### **The new API endpoint BioMate is missing**

`webapps/galaxy/api/workflow_deep_agent.py` — exposes:
```
POST /api/workflows/{wf_id}/invocations/{inv_id}/deep_agent/diagnose
POST /api/workflows/{wf_id}/invocations/{inv_id}/deep_agent/fix
GET  /api/workflows/{wf_id}/invocations/{inv_id}/deep_agent/sessions
```

Plus a Vue frontend panel (`client/src/components/WorkflowInvocationState/DeepAgentDiagnosis.vue`). BioMate uses React, so the panel would need to be rewritten — but the API is what matters.

#### **What the hybrid strategy looks like in practice**

From `AUTOFIX_HYBRID_STRATEGY.md` (and the architecture diagram):

```
Error → Tier 1 (rule fixers, 9 of them) ──┐
                  ↓ all miss              │ stop_on_first_success=True
                  ↓                       │
              Tier 2 (DeepAgentFixer)     │
                  ↓ Claude Sonnet 4       │
                  ↓ ~$0.008/call          │
                  ↓ 8-15s                 │
              FixPlan ◀━━━━━━━━━━━━━━━━━━━┘
                  ↓
            WorkflowRestarter
                  ↓
              queue_invoke()
```

Claimed metrics (unverified): **98% error coverage, 80% cost reduction vs. all-LLM**, **<1ms** for the 90% covered by Tier 1, **8–15s** for the remaining 10% that reaches Tier 2. Tier 2 diagnostic accuracy ~85%, fix success ~75% (some diagnoses are correct but require human action).

---

### B. The four other capabilities

#### **B1. Workflow Timing Logger** (small, self-contained)

`lib/galaxy/jobs/runners/workflow_timing_logger.py` plus `analyze_workflow_timing.py`.

Auto-tracks Nextflow execution time across **15+ phases and sub-phases**: `workflow_submission`, `data_preparation`, `nextflow_execution`, `output_collection`, `monitoring`, plus nested ones like `s3_upload`, `container_startup`, `task_queuing`, `task_running`, `task_data_transfer`, etc. Writes `workflow_timing.json` (machine-readable) and `workflow_timing_report.txt` (human-readable bottleneck report) into the workflow work directory.

Bottleneck identification automatically flags phases that take >30% of total time, >60s average, or >10× variance. The CLI tool `analyze_workflow_timing.py` cross-compares timings across N workflows and exports CSV for dashboards.

**Galaxy coupling: minimal.** Uses only `pathlib`, `json`, `logging`, `dataclasses`. No `galaxy.*` imports.

**Why BioMate would want it:** would surface "the auto-loop took 12 minutes; 8 of them were waiting in the Batch queue" type insights that the current logs don't expose cleanly.

#### **B2. AI Tool Compatibility Checker** (standalone FastAPI service)

`lib/galaxy/ai/compatibility_checker/` — Flask/FastAPI app with a Tailwind frontend.

Validates new Docker images before integration along five dimensions:
1. **ENTRYPOINT conflict** — detects hardcoded ENTRYPOINT that blocks Galaxy/Nextflow wrapping
2. **CLI interface** — parses `--help` to infer argparse vs. positional argument style
3. **GPU support** — checks for CUDA libs, validates nvidia-docker compatibility
4. **Dependency completeness** — Python packages, system libs, NumPy ABI version
5. **Resource estimates** — memory footprint, CPU cores, GPU memory

API surface:
```
POST /api/v1/tools/check                         # queue a check
GET  /api/v1/tools/{check_id}/status             # poll
GET  /api/v1/tools/{check_id}/report             # full CompatibilityReport
GET  /api/v1/tools/{check_id}/templates/{type}   # auto-generated wrapper Dockerfile / Nextflow process / Galaxy tool.xml
```

Returns a score 0–100, grade A–F, integration complexity (simple/medium/complex), estimated integration time.

**Galaxy coupling: minimal.** Zero `galaxy.*` imports in the core class. The FastAPI wrapper is a thin shell.

**Why BioMate would want it:** this is exactly the entry-point of the BioMate `auto_update/` pipeline. The colleague's checker is more thorough than the current `feasibility_checker.py` and could replace or augment it.

#### **B3. Prometheus monitoring stack** (Galaxy webapp integration + Grafana dashboards)

Three layers:

1. **Middleware** (`lib/galaxy/webapps/galaxy/middleware/prometheus_middleware.py`) — Starlette `BaseHTTPMiddleware` that instruments every HTTP request. Normalizes dynamic URL paths (`/workflows/123` → `/workflows/{id}`) to prevent metric-cardinality explosion. Exposes `/api/metrics` for Prometheus scraping.

2. **Metric definitions** (`lib/galaxy/monitoring/__init__.py`) — Counters, gauges, histograms across:
   - **HTTP**: `galaxy_http_requests_total`, `galaxy_http_request_duration_seconds`, `galaxy_http_active_requests`
   - **Workflows**: `galaxy_workflow_executions_total`, `galaxy_workflow_duration_seconds`, `galaxy_workflow_active_executions`
   - **Jobs**: `galaxy_job_submissions_total`, `galaxy_job_queue_size`, `galaxy_job_wait_time_seconds`
   - **GPU**: `galaxy_gpu_job_executions_total`, `galaxy_gpu_utilization_percent`, `galaxy_gpu_memory_used_bytes`
   - **AI/LLM**: `galaxy_ai_llm_calls_total`, `galaxy_ai_llm_duration_seconds`, `galaxy_ai_llm_tokens_total`, `galaxy_ai_confidence_score`
   - **DB**: `galaxy_db_query_duration_seconds`, `galaxy_db_connections_active`

3. **Three Grafana dashboards** (full JSON in `config/grafana_dashboard_*.json`):
   - **GPU Workflows** — success rate, duration distribution, queue wait by GPU type, utilization heatmap, top GPU tools
   - **System Health** — QPS, P50/P95/P99 latency, active workflows, error rate, slowest endpoints, DB latency, CPU/mem
   - **User Billing & Revenue** — total revenue, ARPU, conversion funnel, churn, revenue by service/tier, daily trend

**Galaxy coupling: moderate-high.** Middleware is FastAPI/Starlette specific. Metric labels reference Galaxy-specific concepts (workflow_id, tool_id) — these would need to map to BioMate's invocation IDs.

**Why BioMate would want it:** BioMate has billing/telemetry but no granular real-time observability of *what's running* and *how long every API call takes*. The dashboards alone would be very valuable.

#### **B4. BioMni-Tools optimized Docker images** (Docker + build automation only)

`docker/biomni-tools-split/` — four Dockerfiles that split the monolithic 3.3 GB `biomni-tools` image into:

| Image | Size | Tools |
|---|---|---|
| `Dockerfile.base` | 211 MB | numpy 1.24.3, scipy, pandas, biopython, rdkit, aws-cli v2 |
| `Dockerfile.molecular` | 800 MB total | base + autodock-vina 1.2.5 (binary), meeko, openbabel, gemmi, sklearn, matplotlib, plotly, pubchempy |
| `Dockerfile.rna` | 600 MB total | base + viennarna 2.6.4 |
| `Dockerfile.full-optimized` | 2.0 GB total | everything (drop-in replacement) |

Strategy: multi-stage builds, binary substitution (Vina as GitHub release instead of pip), aggressive `strip --strip-unneeded` on `.so` files, deletion of test directories and `.pyc`. Build orchestrated via `docker buildx` jobs submitted to AWS Batch.

Claimed savings: **RNA image 93% smaller, molecular image 90% smaller, full image 39% smaller, STATE 33% smaller, ProFAM 38% smaller**.

**Galaxy coupling: zero.** Pure Dockerfiles + bash scripts.

**Why BioMate would want it:** every workflow cold-start time is dominated by image pull. A 93% reduction in image size translates almost linearly to startup time savings on Batch.

---

## Part 2 — Deep Agent integration plan for BioMate

### What we already have

BioMate's `backend/lib/galaxy/ai/workflow_ops/autofix/` already contains the **entire Deep Agent core framework** (likely from the earlier integration round):

| File | Status |
|---|---|
| `agent.py` (DeepAnalysisAgent, 26.6 KB) | ✅ Byte-identical to galaxy/dev |
| `toolkit_v2.py` (EnhancedToolKit, 23.1 KB) | ✅ Byte-identical |
| `iterative_debugger.py` (IterativeDebugger, 20.8 KB) | ✅ Byte-identical |
| `autofix3_orchestrator.py` (AutoFix3 outer loop, 13.9 KB) | ✅ Byte-identical |
| `tools/` (read_file, bash_command, grep_search, file_operations) | ✅ Present |
| `llm_client.py` (UnifiedLLMClient, 16.1 KB) | ⚠️ Slightly different (62 bytes — likely a model-name patch or comment) |
| `webapps/galaxy/api/autofix3.py` | ✅ Present (needs wiring verification) |
| `enhanced_autofix.py` (orchestrator wrapper) | ✅ Present |
| `orchestrator.py` (AutoFix v1) | ✅ Present |
| Tier 1 rule fixers (8 of them) | ✅ Present |

### What's missing

| Component | Action | Size |
|---|---|---|
| `fixers/deep_agent_fixer.py` | **COPY** | 23 KB |
| `fixers/llm_universal_fixer.py` | **COPY** | 33 KB |
| `fixers/pure_llm_fixer.py` | **COPY** | 21 KB |
| `fixers/llm_learning_fixer.py` | **COPY** | 17 KB |
| `fixers/parameter_validation_fixer.py` | **COPY** | 19 KB |
| `fixers/cpu_resource_fixer.py` | **COPY** | 9 KB |
| `fixers/docker_daemon_fixer.py` | **COPY** | 6 KB |
| `deep_log_analyzer.py` | **COPY** | — |
| `error_log_parser.py` | **COPY** | — |
| `dataset_validator.py` | **COPY** | — |
| `webapps/galaxy/api/workflow_deep_agent.py` | **COPY + wire** | — |
| `llm_client.py` | **DIFF + merge** | 62B delta |

### Integration phases

#### **Phase 0 — Verify the existing framework actually runs** (½ day)

Before adding new files, prove that what's already in BioMate works. The risk: code is present but never imported / wired, so it could be quietly broken.

1. Find the API route registration for `autofix3.py`. Check `backend/lib/galaxy/webapps/galaxy/api/api_router.py` or wherever BioMate registers FastAPI routes. If not registered, register it.
2. Confirm `agent.py`'s imports resolve in BioMate's environment. The Galaxy version imports from `galaxy.ai.workflow_ops.*` — same path layout in BioMate (under `backend/lib/`). Verify no missing module.
3. Manually trigger `POST /api/workflows/{wf}/invocations/{inv}/autofix3/run` against a known-failed Nextflow invocation (CryoEM with bad S3 path is a quick reproducer).
4. If it errors out, **fix the wiring before importing more files.** Likely fixes: missing `AIFixAuditLog` ORM model, missing `UserCloudPreferences` table, or the `WorkflowInvocation` import. These are the canonical Galaxy-vs-BioMate decoupling points.

**Deliverable**: a successful `autofix3` API call that returns a session_id and at least one attempt, even if the diagnosis is wrong. This proves the *framework* is alive.

#### **Phase 1 — Port the missing fixers** (½ day)

Once Phase 0 passes, copying the new fixers is mechanical:

1. From `galaxy_nextflow`:
   ```bash
   cd /home/yzhang/biomate
   for f in deep_agent_fixer.py llm_universal_fixer.py pure_llm_fixer.py \
            llm_learning_fixer.py parameter_validation_fixer.py \
            cpu_resource_fixer.py docker_daemon_fixer.py; do
     git -C galaxy_nextflow show origin/dev:lib/galaxy/ai/workflow_ops/autofix/fixers/$f \
       > backend/lib/galaxy/ai/workflow_ops/autofix/fixers/$f
   done
   for f in deep_log_analyzer.py error_log_parser.py dataset_validator.py; do
     git -C galaxy_nextflow show origin/dev:lib/galaxy/ai/workflow_ops/autofix/$f \
       > backend/lib/galaxy/ai/workflow_ops/autofix/$f
   done
   ```

2. Each fixer must inherit from `BaseAutoFixer` and implement `detect_issues`, `generate_fix_plan`, `apply_fix`. Open each file and:
   - Resolve any `from galaxy.X import Y` that refers to Galaxy-only models. The likely offender is `UserCloudPreferences` (budget tracking); either stub it or wire it to BioMate's billing system.
   - For `deep_agent_fixer.py`: it imports `DeepAnalysisAgent` and `EnhancedToolKit`. Both already exist in BioMate — no change needed.
   - For `parameter_validation_fixer.py`: it does `boto3.client('s3').head_object()` — verify BioMate's IAM role has `s3:GetObject` on the right buckets.
   - For `llm_learning_fixer.py`: it stores past fixes in memory only. **This is a future enhancement opportunity** — persist to SQLite or Postgres for cross-run learning.

3. Register the new fixers in the orchestrator. Open `backend/lib/galaxy/ai/workflow_ops/autofix/__init__.py` (or wherever the fixer list is built) and add them. **Order matters** — put `deep_agent_fixer` *last* so it only fires when rule fixers miss.

4. Run the test suite:
   ```bash
   cd backend && pytest lib/galaxy/ai/workflow_ops/autofix/tests/
   ```

#### **Phase 2 — Wire the Deep Agent API** (½ day)

1. Copy `workflow_deep_agent.py`:
   ```bash
   git -C galaxy_nextflow show origin/dev:lib/galaxy/webapps/galaxy/api/workflow_deep_agent.py \
     > backend/lib/galaxy/webapps/galaxy/api/workflow_deep_agent.py
   ```

2. Register routes in `api_router.py` (BioMate's FastAPI route registry). Same pattern as `autofix3.py`.

3. Reload the Galaxy backend:
   ```bash
   kill -HUP $(pgrep -f 'gunicorn.*8081' | head -1)
   ```

4. Smoke test:
   ```bash
   curl -X POST http://localhost:8081/api/workflows/$WF/invocations/$INV/deep_agent/diagnose \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $KEY"
   ```

#### **Phase 3 — Frontend** (1 day, optional for backend-first MVP)

The Galaxy frontend is Vue; BioMate is React. Port `DeepAgentDiagnosis.vue` to a React component in `frontend/client/src/components/`. The data contract is simple:

```ts
type DiagnosisResponse = {
  session_id: string;
  attempts: Array<{
    attempt_number: number;
    status: 'success' | 'failed' | 'duplicate' | 'timeout';
    confidence: number;
    root_cause: string;
    suggested_params: Record<string, any>;
  }>;
  final_result: { root_cause: string; recommended_fix: {...} };
};
```

The natural home is the auto-loop panel (`nextflow-workflow-viewer.tsx`) — render a "Deep Agent diagnosis" expandable card when an invocation fails. Tie into the existing remediation panel UI.

#### **Phase 4 — Verification on a real failure** (½ day)

Per the project's iterative loop rule: implement → test → record → audit → fix → repeat.

1. Identify a recent failed Batch invocation (CryoEM gap test runs in dev are good candidates — they fail on bad S3 paths or missing params).
2. Trigger the auto-fix pipeline on it.
3. Verify:
   - Tier 1 fires first
   - If miss, Tier 2 (DeepAgent) fires
   - Suggested fix is applied
   - Workflow restarts (via Nextflow executor, not Galaxy queue_invoke — BioMate doesn't use Galaxy's invocation API the same way; check `WorkflowRestarter` for assumptions)
   - Result is logged
4. Run on dev EC2 via `scripts/sync_to_dev.sh`.

**Critical decoupling point — `WorkflowRestarter`**: this is the Galaxy-specific piece. Galaxy uses `queue_invoke()` on the Workflows API; BioMate has its own `nextflow_executor.py` and `nextflow_workflow_runner.py`. Read `workflow_restarter.py` and replace the `queue_invoke` call with a BioMate-native restart. This is the only piece of the integration that requires real adaptation (not just copy).

### Total estimated effort

| Phase | Effort | Risk |
|---|---|---|
| Phase 0 (verify framework) | ½ day | **High** — may uncover hidden brokenness |
| Phase 1 (copy fixers) | ½ day | Low |
| Phase 2 (wire API) | ½ day | Low |
| Phase 3 (React UI) | 1 day | Medium (UI design) |
| Phase 4 (real-failure verification + dev sync) | ½ day | Medium (`WorkflowRestarter` rewrite) |
| **Total** | **~3 days** | Mostly in Phase 0 and Phase 4 |

---

## Part 3 — Can BioMate leverage the DeepAgent framework *beyond* AutoFix?

**Yes — this is the more interesting question.** The DeepAgent + EnhancedToolKit combo is essentially a *general-purpose Claude tool-use agent with a sandboxed filesystem + bash*. It's not autofix-specific; the autofix use case is just one consumer.

Concrete opportunities, ranked by leverage:

### **L1. Parameter extraction for the param_prefill benchmark** (high leverage)

`evaluation/datasets/param_prefill/cases.yaml` is at 61.7% (target ≥70%). Current extraction is a hybrid of regex rules + a single LLM call (`ai_assistant.py`). Many of the failures come from cases where the LLM has to *guess* a parameter value when it could *verify* it.

Example: query says "use the latest GTF from Ensembl 110". Current pipeline either invents a URL or fails. With DeepAgent, the LLM can:
- `bash_command: curl -I https://ftp.ensembl.org/pub/release-110/gtf/homo_sapiens/`
- See if the file exists
- Return the verified URL

The same pattern applies to:
- Verifying S3 paths exist before scheduling (today fails silently at runtime)
- Discovering the right reference genome version from a user's organism
- Extracting accession numbers from a paper (use `read_file` on an uploaded PDF/text)

**Effort**: 1–2 days. Wrap `DeepAnalysisAgent.analyze()` with a different prompt and a different toolkit subset (no `edit_file`, just `read_file` + `bash` + `curl`-style operations).

### **L2. Routing layer for the long tail** (medium-high leverage)

Today routing (`galaxy-assistant.ts` + workflow index) handles ~80% of cases via dense+sparse retrieval. The remaining 20% are ambiguous or require domain knowledge the index doesn't surface.

Use DeepAgent as a **fallback routing brain** when the top-K candidates have low confidence:
- LLM reads the user's full conversation history (`get_workflow_params`-style tool)
- Greps the workflow DB for keywords it generates
- Decides between candidates with a structured rationale

**Effort**: 1 day. Already have most infra (Haiku classifier exists). The DeepAgent toolkit just adds the verification step.

### **L3. CRO compliance auto-audit** (medium leverage)

CRO compliance workspace already does manual gating. DeepAgent could **auto-audit** uploaded CRO packages:
- `read_file` on each uploaded report
- `grep` for required regulatory keywords (21 CFR Part 11 markers, e.g.)
- `bash` to validate file checksums match manifest
- Return a structured "compliant / non-compliant + reasons" report

**Effort**: 2 days. Mostly prompt engineering and regulatory-aware tools.

### **L4. Workflow DB curation (auto_update pipeline)** (lower leverage but high-novelty)

The `auto_update/` pipeline discovers new tools from GitHub. DeepAgent could replace or augment `feasibility_checker.py`:
- `bash_command: docker pull <image>` (sandboxed)
- `bash_command: docker run --entrypoint /bin/sh <image> -c "ls /usr/local/bin"`
- Read the tool's README and infer the right Galaxy `tool.xml` schema
- This is *exactly* what `compatibility_checker/` does, but more general

**Effort**: 3–5 days. Overlaps with capability B2 (AI Tool Compatibility Checker) — consider porting both together.

### **L5. Bug triage / log explanation in chat** (medium leverage, immediate user value)

When a user asks "why did my workflow fail?", today the answer is mostly a copy-paste of the error log + Haiku summary. DeepAgent could be wrapped as a **chat tool** that the AI assistant invokes when it detects "error", "failed", or "didn't work" in the user's message:
- Reads the relevant invocation files
- Investigates root cause
- Returns a human explanation + suggested next action

This is the most *visible* user-facing benefit of DeepAgent, more visible than autofix itself.

**Effort**: 1 day. Wrap as an `Anthropic Tool Use` block in the chat assistant's tool list.

### What NOT to do

- **Don't use DeepAgent for routine inference.** It's expensive (~$0.008/call, 8–15s) and the rule layer / shallow LLM call is faster and cheaper for 90%+ of cases. Keep the hybrid strategy: rules first, DeepAgent only on miss.
- **Don't expose `bash_command` to untrusted user input directly.** The toolkit sandbox is solid but designed for internal use. If user-facing, add an additional input validation layer.
- **Don't run DeepAgent without the budget cap.** `llm_client.py` enforces a daily budget — make sure it's wired before opening the API to users.

---

## Recommendation

1. **Start with Phase 0** of the integration plan (verify what's already there actually works). This is the single highest-information action — if `autofix3` already runs end-to-end in BioMate, the rest of the integration is trivial copying. If it doesn't, we surface the real blockers before investing in copying more code.

2. **In parallel**, port the **Workflow Timing Logger** (capability B1) — 30 minutes of work, immediate observability win, no integration risk.

3. After Phase 0 succeeds, do Phases 1–2 (port fixers + wire API) in a single session — ~1 day.

4. **Defer the React frontend (Phase 3)** until backend is verified. Backend-only via API is fully usable for internal testing.

5. **Leverage opportunity L1 (DeepAgent for param_prefill)** is the highest-leverage non-autofix use — schedule it as the next session after AutoFix v3 lands. The param_prefill benchmark gap (61.7% → 70%) directly benefits.

6. **Skip capability B3 (Prometheus stack)** for now — BioMate's existing telemetry-service + billing dashboards cover most of the same ground. Revisit when admin-side observability becomes a felt pain.

7. **Capability B4 (split Docker images)** — schedule as standalone infra work, decoupled from this integration. High ROI on cold-start time.
