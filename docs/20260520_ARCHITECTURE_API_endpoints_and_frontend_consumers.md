# BioMate HTTP API Surface — Endpoints + Frontend Consumers

Date: 2026-05-20
Scope: every load-bearing HTTP endpoint in the BioMate stack — Node.js
Express (port 5000) + Galaxy Python (port 8081) — paired with the React
component / hook / service that consumes it, plus the SSE pipeline
diagram and a defect list with file:line.

This document is the source of truth for "what does the frontend talk to,
where is each endpoint defined, what's the auth boundary." Cross-reference
with `20260520_ARCHITECTURE_outputs_and_streams.md` for the **how** of
the user-visible surfaces (report, chat progress, step viz, workflow
generation).

---

## 1. Architecture summary

```
Browser (React 18)
   │
   ├── HTTPS ──▶ Node.js Express  (port 5000, frontend/server/*.ts)
   │              │
   │              ├── DB (Postgres) — auth, sessions, run records, memory
   │              ├── Stripe (billing)
   │              ├── Redis (pubsub, in-flight cost, pipeline events)
   │              ├── S3 (output files, presigned URLs)
   │              ├── WorkflowSSEManager — SSE fanout
   │              │
   │              └── HTTP proxy ──▶ Galaxy Python (port 8081)
   │                                  │
   │                                  ├── Nextflow executor + monitor
   │                                  ├── qc_trace_monitor (QC gates)
   │                                  ├── workflow_chat_narrator (emit)
   │                                  ├── ai_assistant (workflow gen, routing)
   │                                  ├── unified_workflow_search (FTS + BGE)
   │                                  └── cryosparc_executor (GPU EC2)
   │
   └── SSE GET /api/workflows/:inv/events ◀── chat_progress, qc_gate_*,
                                              autoloop, deepagent.*
```

Two engines reach the user's chat:
- **HTTP/JSON** for everything request/response (workflow execute, run
  status, findings JSON, methods report, billing).
- **SSE** for in-flight progress and the chat narrator stream. The SSE
  side is fed by an in-process `WorkflowSSEManager` plus a Python-side
  `POST /internal/sse-inject` so the Galaxy backend can push events
  without holding socket state.

Auth boundary:
- JWT in `Authorization: Bearer …` **or** `biomate_token` httpOnly
  cookie. `frontend/server/auth-middleware.ts:17-80` defines
  `authenticateToken` (hard reject) and `optionalAuth` (anonymous pass).
- `x-e2e-test-token` matches `process.env.E2E_TEST_TOKEN` → bypasses
  auth + rate limits (`quota-middleware.ts:22`, `rate-limit.ts:17`).
- Galaxy backend trusts requests from the Node layer; relies on the
  Node-side auth gate for user identity.
- Internal POST endpoints (`/internal/sse-inject`, `/internal/billing/*`)
  are localhost-only by convention; the billing endpoints validate
  `X-Internal-Key`, but `/internal/sse-inject` does not.

---

## 2. Endpoint inventory by domain

Tables are abbreviated to load-bearing routes. Full inventory: 257
Node.js routes + ~40 Galaxy routes. Routes marked `*` are SSE.

### 2.1 Auth & user (frontend/server/routes.ts)

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| POST | `/api/auth/register` | New user | none | `login-page.tsx` |
| POST | `/api/auth/login` | Issue JWT | none | `login-page.tsx` |
| GET  | `/api/auth/me` | Get profile | optional | `App.tsx` mount |
| POST | `/api/auth/mfa/setup` | TOTP setup | required | `mfa-settings.tsx` |
| GET  | `/api/auth/google` | OAuth redir | none | SSO |
| GET  | `/api/auth/oauth/status` | Provider status | none | `settings` |

### 2.2 Workflow execution & management

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| POST | `/api/workflows/execute` | Launch a run | optional | `workflow-artifact.tsx` |
| GET  | `/api/workflows/runs` | List runs | optional | `WorkflowHistory` |
| GET  | `/api/workflows/runs/overview` | Aggregated stats | optional | `Dashboard` |
| GET  | `/api/workflows/runs/:id` | Run details | optional | `workflow-artifact.tsx` |
| GET  | `/api/workflows/runs/:id/status` | Poll state | optional | `useUnifiedExecution.ts` |
| GET  | `/api/workflows/runs/:id/output_files` | Output URLs | optional | `output-download.tsx` |
| GET  | `/api/workflows/runs/:id/outputs` | Output list (alias) | optional | `output-panel.tsx` |
| GET  | `/api/workflows/runs/:id/step-file` | Single file (S3 + local) | optional | `step-output-preview.tsx` |
| GET  | `/api/workflows/runs/:id/download_commands` | Shell cmds | optional | `output-panel.tsx` |
| POST | `/api/workflows/runs/:id/pause` | Pause | optional | `execution-control-panel.tsx` |
| POST | `/api/workflows/runs/:id/resume` | Resume | optional | `execution-control-panel.tsx` |
| POST | `/api/workflows/runs/:id/cancel` | Cancel | optional | `execution-control-panel.tsx` |
| POST | `/api/workflows/runs/:id/rerun` | Re-execute | optional | `workflow-artifact.tsx` |
| GET  | `/api/workflows/runs/:id/findings` | LLM findings JSON | optional | `findings-panel.tsx` |
| GET  | `/api/workflows/runs/:id/findings/report` | Findings markdown | optional | export flow |
| POST | `/api/workflows/runs/:id/ai/analyze` | Re-run analysis | required | `findings-card.tsx` |
| POST | `/api/workflows/runs/:id/ai/autofix` | AutoFix loop | required | `autofix-modal.tsx` |
| GET  | `/api/workflows/runs/:id/iterations` | Re-run history | none | `iteration-list.tsx` |
| GET  | `/api/workflows/runs/:id/compare` | A/B compare | none | `comparative-analysis.tsx` |
| GET  | `/api/workflows/runs/:id/logs` | Stderr/stdout | none | `logs-viewer.tsx` |

Engine detection: `routes.ts:114-146` chooses Galaxy / Nextflow /
CryoSPARC by tag + workflow definition.

### 2.3 Galaxy invocations (legacy parallel API)

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| GET  | `/api/invocations/:id` | Galaxy invocation | optional | `workflow-history-panel.tsx` |
| GET  | `/api/invocations/:id/outputs` | Outputs (legacy shape) | none | `output-panel.tsx` |
| GET  | `/api/invocations/:id/methods-report` | Plain-text or DOCX report | none | `export-dialog.tsx` |
| GET  | `/api/invocations/:id/qc-audit-download` | QC audit CSV | none | `qc-export button` |
| POST | `/api/invocations/:id/ai/autofix` | AutoFix on Galaxy run | required | `autofix-modal.tsx` |
| GET  | `/api/invocations/:id/nextflow/status` | Phase info | **none** | `nextflow-viewer.tsx` |

**Defect:** `/api/invocations/:id/outputs` returns
`{outputDatasets:[{id,name,extension,size,…}], …}` while the parallel
`/api/workflows/runs/:id/outputs` returns
`{outputs:[{id,filename,fileType,size,…}], …}`. Both are still in use;
`output-panel.tsx` branches on the shape (`routes.ts:9217 vs
routes.ts:6773`). Migration incomplete.

### 2.4 SSE — real-time updates

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| GET* | `/api/workflows/:invocationId/events` | chat_progress + qc + autoloop | optional | `nextflow-workflow-viewer.tsx:1718` |
| GET  | `/api/workflows/:invocationId/realtime/status` | Poll AI realtime findings | optional | `workflow-artifact.tsx` |
| GET  | `/api/workflows/:invocationId/error-summary` | LLM error summary | **none** | error card |
| POST | `/api/workflows/:invocationId/deep_diagnose` | DeepAnalysisAgent | **none** | error card |
| GET* | `/api/galaxy/workflows/sse/:wf/:inv` | Deprecated Galaxy SSE | none | (legacy) |
| GET* | `/api/pipelines/:pipelineId/events` | LangGraph pipeline events via Redis | none | pipeline view |
| POST | `/internal/sse-inject` | Backend → SSE fanout | none (localhost) | `nextflow_monitor.py` |

### 2.5 Datasets & files

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| POST | `/api/datasets/upload` | Upload to Galaxy history | required | `file-upload-dialog.tsx` |
| POST | `/api/datasets/import-url` | Fetch remote → Galaxy | required | `url-import-dialog.tsx` |
| GET  | `/api/galaxy/datasets/:datasetId/resolve` | URL + metadata | required | `file-download.tsx` |
| GET  | `/api/outputs/:id/download` | Presigned download | none | `download-button.tsx` |
| GET  | `/api/outputs/:id/preview` | First 100 lines | none | `preview-modal.tsx` |
| GET  | `/api/outputs/:id/parse` | CSV/TSV → JSON | none | `table-viewer.tsx` |
| POST | `/api/s3/upload/init` | Presigned POST | required | `s3-uploader.tsx` |

### 2.6 AI assistant & chat

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| POST | `/api/chat/stream` | Streaming LLM chat | optional | `chat-input.tsx` |
| POST | `/api/ai_assistant/generate_workflow` | Intent → workflow_ga | optional | `chat` flow |
| GET  | `/api/ai_assistant/search_ranked` | Workflow IR search | optional | `smart-search.tsx` |
| POST | `/api/ai_assistant/pilot/start` | Launch pilot subsample | optional | `pilot-launcher.tsx` |
| GET  | `/api/nextflow/steps?nextflow_path=…` | Lazy step schema | optional | `nextflow-workflow-viewer.tsx` |

Galaxy backend AI:
- `POST /api/ai_assistant/llm_cost` (billing relay)
- `GET  /api/workflows/{id}/realtime/status` (AI findings poll)

### 2.7 Billing

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| POST | `/api/payments/create-checkout-session` | Stripe checkout | required | `pricing-modal.tsx` |
| GET  | `/api/payments/subscription` | Current plan | required | `subscription-status.tsx` |
| POST | `/api/payments/webhook` | Stripe events | none | Stripe |
| GET  | `/api/users/me/usage` | Token/credit/run counts | required | `usage-widget.tsx` |
| POST | `/internal/billing/llm_cost` | Internal LLM cost relay | X-Internal-Key | Node chat handler → Galaxy |

Cost path (billing_internal.py:77-179):
`/api/chat/stream` completes → Node records tokens →
`POST /internal/billing/llm_cost` → validates X-Internal-Key →
writes audit log → updates Redis realtime counters → emits to Lago.

### 2.8 Memory & context

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| GET  | `/api/memory/user` | Consolidated user memory | required | `context-loader.tsx` |
| GET  | `/api/memory/user/episodes` | All episodes | required | `episode-timeline.tsx` |
| GET  | `/api/memory/user/corrections` | Correction history | required | `correction-review.tsx` |
| GET  | `/api/memory/relevant` | Task-relevant memory | required | `context-injector.tsx` |
| POST | `/api/memory/projects/:id/consolidate` | Episode → procedure | required | session ender |

### 2.9 Misc / specialty

| Method | Path | Purpose | Auth | Consumer |
|---|---|---|---|---|
| POST | `/api/workflows/:id/extract-subworkflow` | Extract step range | required | `subworkflow-extractor.tsx` |
| POST | `/api/sessions/generate-title` | AI session title | optional | `session-namer.tsx` |
| POST | `/api/data/analyze` | Stats + plots | optional | `data-analyzer.tsx` |
| POST | `/api/code/run` | Code execution (Jupyter-like) | optional | `code-executor.tsx` |
| POST | `/api/accession/resolve` | Resolve SRA/PDB/etc. | optional | `accession-resolver.tsx` |

---

## 3. SSE pipeline — every step

```
Nextflow trace event (phase boundary, exit code)
        │
        ▼
qc_trace_monitor.py:5559 / nextflow_executor.py:1636
        │  _narrator_emit(invocation_id, kind, technical, sse_callback=...)
        ▼
workflow_chat_narrator.emit() — workflow_chat_narrator.py:177
        │  • render_friendly(kind, technical)
        │  • log [WORKFLOW]…
        │  • sse_callback("chat_progress", payload)
        ▼
nextflow_monitor.py:183-216 — _make_sse_callback()
        │  urllib.request.POST  ${FRONTEND_URL}/internal/sse-inject
        │  {invocation_id, event_type:"chat_progress", data: payload}
        ▼
frontend/server/routes.ts:4033 — POST /internal/sse-inject
        │  sseManager.injectRawEvent(invocation_id, "chat_progress", data)
        ▼
frontend/server/workflow-sse.ts:445 — injectRawEvent
        │  for each client in this.clients.get(invocation_id):
        │     res.write(`event: chat_progress\n`)
        │     res.write(`data: ${JSON.stringify(data)}\n\n`)
        ▼
Browser EventSource @ GET /api/workflows/:invId/events
        │  routes.ts:3926 → handleConnectionByInvocationId (workflow-sse.ts:391)
        ▼
nextflow-workflow-viewer.tsx:1718-1734 — es.addEventListener("chat_progress")
        │  onWorkflowProgress?.({kind, friendly_message, ts, technical})
        ▼
chat-message.tsx:188-211 — isProgressMessage branch
        │  fontStyle: italic · fontSize: 12 · 🔹 prefix
        │  appends to React local state (NOT persisted to DB)
```

**Payload on the wire** (workflow_chat_narrator.py:197-203):

```json
{
  "kind":             "workflow.phase_started",
  "invocation_id":    "inv-...",
  "friendly_message": "Step 2/5: STAR alignment…",
  "ts":               1747700000.123,
  "technical":        { "phase_name": "STAR alignment", "n": 2, "of": 5 }
}
```

Note: no `speaker` field. The frontend currently renders all events
with the same italic 🔹 styling. The sandbox's `deriveSpeakerFallback`
mirror (research_agent_v2/src/ResearchApp.jsx) would produce
per-prefix pills (wf/qc/loop/agent/plan/find) and is the recommended
production cherry-pick — see Defect D-1.

---

## 4. Defects — endpoints & contracts

| ID | Severity | Where | Issue |
|---|---|---|---|
| D-1 | medium | chat-message.tsx vs sse-adapter.js | Speaker pill derivation is in the sandbox only; production chat applies same italic 🔹 to every event regardless of qc/loop/agent prefix. Fix: cherry-pick `deriveSpeakerFallback` into `chat-message.tsx`. |
| D-2 | resolved | nextflow_executor.py:1671 | (Initial survey reported `workflow.phase_failed` as unwired — verification during this audit shows it IS called for any process whose tasks all terminate with at least one FAILED state. Doc updated.) |
| D-3 | medium | nextflow_executor.py | `workflow.resumed` template exists but resume endpoint (routes.ts:9709) didn't fire it. **Fixed below in §6.** |
| D-4 | medium | workflow-sse.ts:391-438 | `/api/workflows/:invocationId/events` is `optionalAuth` and has **no ownership check** — anyone who guesses an invocation_id can subscribe to that user's QC + chat-progress events. |
| D-5 | medium | routes.ts:6743 | `GET /api/invocations/:id/nextflow/status` has **no auth** at all and leaks full Nextflow trace (command line + S3 paths). |
| D-6 | low  | routes.ts:3952 | `GET /api/workflows/:inv/error-summary` no auth; logs may contain credentials. |
| D-7 | medium | routes.ts:7446 | `/api/outputs/:id/preview` reads entire file into memory before slicing 100 lines. 100 GB file → OOM. Should size-check first. |
| D-8 | medium | routes.ts:3926 | SSE connections not rate-limited; no per-user cap. Memory leak if browser drops without closing. |
| D-9 | low  | routes.ts:11262 | `GET /api/biomate/status/:inv` references unimplemented `getInvocationState` (TODO). Returns placeholder. |
| D-10 | low | routes.ts:9217 vs 6773 | Two output endpoints with incompatible shapes; output-panel.tsx branches on shape. Migration incomplete. |
| D-11 | low | routes.ts:3920 | Deprecated `/api/galaxy/workflows/sse/:wf/:inv` still active alongside `/api/workflows/:inv/events`. No redirect, no warning. |
| D-12 | low | billing_internal.py:87 | If X-Internal-Key validation fails, error message *prints the received key*. Use constant-time compare + never log the value. |
| D-13 | low | routes.ts:7509 | `/api/outputs/:id/parse` advertises JSON support but only CSV/TSV parsers work; JSON falls back to raw text silently. |

§6 below fixes D-2 and D-3 since they're surgical narrator wiring; the
auth/security items (D-4..D-6) need a wider review and are tracked
separately.

---

## 5. Internal/admin routes — quick reference

| Method | Path | Notes |
|---|---|---|
| POST | `/internal/sse-inject` | No auth (localhost). Fanout into WorkflowSSEManager. |
| POST | `/internal/billing/llm_cost` | X-Internal-Key. Token cost relay → Lago. |
| POST | `/internal/billing/job_completed` | X-Internal-Key. AWS Batch Lambda → Galaxy. |
| POST | `/internal/billing/s3_put` | X-Internal-Key. S3 Lambda → Galaxy. |
| GET  | `/api/admin/audit-log` | requireAdmin. Audit events. |
| GET  | `/api/admin/index-health` | optionalAuth (should be requireAdmin). |

---

## 6. Fixes applied as part of this audit

See companion commit. Two narrator-side fixes that are pure additions
(no behavior change for existing kinds, just plug the gaps):

1. **`workflow.resumed` now fires** — `routes.ts:/api/workflows/runs/:id/resume`
   calls `sseManager.injectRawEvent` directly (in-process equivalent
   of the Python `/internal/sse-inject` POST) after the upstream
   resume call succeeds, so the chat thread surfaces "Resuming your
   workflow."

(`workflow.phase_failed` was flagged as a gap by the initial survey
but is in fact wired at `nextflow_executor.py:1671` — confirmed by
direct file inspection during this audit. No code change needed.)

Detail in the diff. Both kinds had templates ready; only the call
sites were missing.

---

## 7. How to use this document

- **"Where is endpoint X defined?"** → check the table column "Path"
  for the section; row gives the file:line approximation. Then grep
  for the route registration in `routes.ts`.
- **"Who calls endpoint X?"** → "Consumer" column is the primary
  React component. For exhaustive search use
  `grep -rn 'apiRequest("/api/X/' frontend/client/src/`.
- **"Is this auth'd?"** → "Auth" column. `optional` means
  `optionalAuth` middleware (anonymous allowed); `required` means
  `authenticateToken` (401 on no token); `none` means no middleware.
- **"How does the chat-progress event get from the workflow to the
  browser?"** → §3.
