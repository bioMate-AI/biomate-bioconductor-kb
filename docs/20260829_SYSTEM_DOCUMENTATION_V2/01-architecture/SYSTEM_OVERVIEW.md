# 01 · System Overview

**Verified 2026-08-29.** See the [README](../README.md) for corrections to stale facts and the full reading guide.

---

## 1. What BioMate is

A full-stack, AI-driven bioinformatics / drug-discovery / clinical platform. Users converse in natural language; the platform classifies intent, selects or composes a real executable workflow, prefills its parameters, runs it on cloud compute, streams live progress, grades results against QC gates, auto-debugs failures, and returns downloadable outputs + a findings report — all inside one chat + right-panel UI.

## 2. Process & network topology

Three long-lived processes plus cloud compute:

| Process | Tech | Host port (dev-local) | Container port | Role |
|---------|------|----------------------|----------------|------|
| **Frontend server** | Node 18 / Express (ESM, `tsx`/`esbuild`) | 5000 | 3000 | Serves the React SPA, handles auth, chat streaming, SSE fan-out, proxies `/api/*` scientific calls to Galaxy |
| **Galaxy backend** | Python 3.9 / gunicorn (4 workers, preload) | 8081 | 8080 | AI assistant, workflow generation/search, Nextflow executor, QC, billing internals |
| **Reference design** | static HTTP | 7779 | — | Design-reference HTML (UX parity target) |

Cloud/managed: **AWS Batch** (Nextflow tasks), **EC2** (CryoSPARC), **ECR** (containers), **ElastiCache Redis** (run-state + billing ledger), **S3** (workdirs/outputs/data), **Lambda** (billing events), **PostgreSQL** (app + LTM), **Stripe**, **LLM providers** (Anthropic/Google/OpenAI/DeepSeek/Zhipu/local).

```
Browser (React SPA)
   │  HTTPS + SSE
   ▼
Node/Express (frontend/server)  ──proxy /api/*──►  Galaxy backend (Python/gunicorn)
   │  Stripe, OAuth, JWT, SSE                          │  AI assistant, generation, search
   │                                                   │  Nextflow executor
   ▼                                                   ▼
PostgreSQL (app + LTM)                    Nextflow HEAD (local subprocess)
                                                       │  submits tasks
                                                       ▼
                                          AWS Batch (CPU/GPU queues) ──► S3 outputs
                                          EC2 + CryoSPARC API (cryo-EM path)
   Redis (run-state, billing ledger) ◄── both backends
```

## 3. Technology stack (verified versions)

- **Client:** React 18.3.1, Vite 5.4.19, TypeScript 5.6.3, wouter (router), @tanstack/react-query 5.60, Tailwind 3.4, Radix UI, react-hook-form + zod, react-markdown, recharts + 3Dmol, TipTap.
- **Server:** Node 18, Express (ESM), Drizzle ORM 0.39 (pg + better-sqlite3), `@anthropic-ai/sdk` 0.68, `@google/generative-ai` 0.24, `openai` 5.20, jsonwebtoken + bcrypt + passport + speakeasy (MFA), Stripe 19.1, AWS SDK v3, `ws` 8.18.
- **Backend:** Python 3.9 (bookworm — pinned for JDK17/glibc 2.36 to avoid an AWS-CRT JVM SIGSEGV), gunicorn (sync, 4 workers), FastAPI-style routers inside Galaxy, sentence-transformers (BGE-small / MiniLM), Nextflow 25.10.5 (pinned, pre-cached in the image).
- **Data:** PostgreSQL 14+ (app + LTM), SQLite (`galaxy_ai_tools.db` FTS5 + sqlite-vec; Galaxy `universe.sqlite`), Redis (ElastiCache).

## 4. Two canonical request lifecycles

### 4.1 Chat → workflow suggestion
1. Client `POST /api/chat/stream` (`routes.ts:5535`, `optionalAuth`).
2. `GalaxyAssistant` (`galaxy-assistant.ts`) classifies intent, builds a domain-catalog + routing prompt, streams tokens; on a workflow intent it calls the backend `POST /api/ai_assistant/generate_workflow`.
3. Backend `AIAssistant.generate_workflow_unified` (`ai_assistant.py:3956`): LTM-correction inject → fast-path shortcuts → chain lookup → iterative search trials → disambiguation gate → LLM routing verify → confidence-tiered strategy (template-reuse / template-adapt / compose-from-scratch via `NextflowComposer`).
4. Returns a `workflow_ga`-adjacent dict (name, domain, rationale, params with rule+LLM prefill, `nextflow_path`). Steps are lazily fetched via `/api/nextflow/steps` when `steps = {}`.
5. Client renders AI text + a workflow card; opening it populates the right-panel `nextflow-workflow-viewer`.

### 4.2 Run → live progress → results
1. Client confirms → `POST /api/nextflow/execute` (`nextflow_executor.py:5037`).
2. Executor mints `run_id`/`invocation_id`, writes a `configuring` record to both the in-process `_runs[]` dict **and** the Redis run-state store, spawns a background launch thread, returns immediately (async-return dodges undici's header timeout).
3. `_launch_nextflow_head` acquires a bounded-concurrency semaphore and `Popen`s the Nextflow head with FD-decoupled logging; tasks route to AWS Batch (CPU queue `biomate-nextflow-queue`, GPU `biomate-gpu-spot-queue`).
4. A QC-monitor thread tails `workflow-trace.txt` and POSTs progress to `{FRONTEND_URL}/internal/sse-inject`; the Node `WorkflowSSEManager` fans events to the browser `EventSource`.
5. On exit, `_stream_logs` applies false-success/false-failure salvage, writes terminal state, runs S3 QC + the ADMET/cryo auto-loop (advisory), and narrates a chat line.
6. If a gunicorn worker recycled mid-run, the per-worker `CompletionPoller` detects the orphaned PID, `finalize_orphaned_run` infers the return code from disk/S3, updates Redis + the Postgres `execution_runs` row, and emits the terminal SSE.

## 5. Process-model invariants (load-bearing, do not "simplify")

- **`_runs_lock` is a reentrant `RLock`** — locked sections call lock-taking helpers; a plain `Lock` self-deadlocks (incident 2026-06-30).
- **Nextflow head logging is FD-decoupled** (`stdout=logfile, start_new_session=True`) — reverting to `PIPE` blocks the JVM when gunicorn recycles.
- **`RUN_STATE_STORE=redis` must be set** or cross-worker orphan completion silently falls back to in-memory (no crash, but the fix is inactive).
- **Gunicorn is `workers=4, max_requests=3000, jitter=300, preload=true`** — the old "1 worker / ~3-min recycle" era is over; don't diagnose dev issues with it.
- **`FRONTEND_URL` on the backend must match the host clients connect to**, or SSE injects are dropped ("No clients … dropping event").

## 6. Cross-cutting: security, failure modes & scaling

The lifecycles in §4 are happy paths. The load-bearing cross-cutting concerns:

### 6.1 HTTP-layer security (Node)
Separate from the billing 402/429 quota gate ([BILLING_QUOTA](../06-billing-auth/BILLING_QUOTA.md)):
- **Rate limiting** (`frontend/server/rate-limit.ts`, `express-rate-limit`): `apiLimiter` 100 req / 15 min (general API), `authLimiter` 10 / 15 min (login), `registerLimiter` 3 / 1 h, `passwordResetLimiter` 3 / 1 h, `emailVerificationLimiter` 1 h window. IP-level — a boundary distinct from per-user spend quota.
- **Security middleware** (`frontend/server/security-config.ts`): `helmet` (HSTS + Content-Security-Policy, env-gated), `cors` (`CORS_ORIGINS` allowlist), CSRF via `csrf-sync`.
- **Auth boundary** ([AUTH_CREDENTIALS_SANDBOX](../06-billing-auth/AUTH_CREDENTIALS_SANDBOX.md)) + **code-execution boundary** (the default-off gVisor sandbox).

### 6.2 Failure modes to reason about
- **Chat-stream mid-token failure** — `/api/chat/stream` streams SSE; if the LLM stream errors mid-token or undici/SSE disconnects, the client sees a partial message. `optionalAuth` means an unauthenticated caller degrades (no persistence) rather than 401. There is no server-side partial-message replay — a reconnect restarts the turn.
- **Cross-datastore partial write** — the orphan-finalizer writes Redis run-state **and** POSTs the Postgres `execution_runs` row. These are **not transactional**: if the Redis write lands but the Postgres POST fails (or vice versa), the two stores disagree until the next poll. The completion lock (`:{id}:completing`, 120 s TTL) prevents *double*-finalize but not a split write; there is no explicit reconciliation job. **Landmine:** if `RUN_STATE_STORE=redis` is unset in prod, cross-worker completion silently no-ops (in-memory only) — runs launched on a since-recycled worker never finalize.
- **False-success / false-failure salvage** — real, and load-bearing (see [WORKFLOW_EXECUTION §1](../03-backend-ai/WORKFLOW_EXECUTION.md)); the executor deliberately overrides the raw exit code from disk/S3 evidence.

### 6.3 Concurrency & scaling limits
- **Nextflow heads:** bounded by `BIOMATE_NF_MAX_CONCURRENT=10` per process (→ 503 after a 300 s wait). Aggregate ceiling across 4 gunicorn workers is not centrally coordinated — it is ~10 × per-worker, gated further by AWS Batch queue depth/quotas.
- **Embed server:** a single shared process over one Unix socket (`/tmp/biomate_embed.sock`) — a per-host serialization point for vector search; workers fall back to FTS-only if it's down.
- **CryoSPARC:** one `g6.12xlarge` EC2 instance per run path — effectively serialized, with an idle auto-terminate alarm; not horizontally scaled.
- **gunicorn:** `workers=4, preload=true` (copy-on-write); `max_requests=3000` recycles are now rare/staggered.

## 7. Where to look (top-level map)

| Concern | Path |
|---------|------|
| Chat + LLM orchestration (Node) | `frontend/server/galaxy-assistant.ts` |
| All Node API routes | `frontend/server/routes.ts` |
| AI assistant (Python) | `backend/lib/galaxy/ai/ai_assistant.py` + `webapps/galaxy/api/ai_assistant.py` |
| Workflow/tool search | `backend/lib/galaxy/ai/unified_workflow_search.py`, `unified_tool_search.py` |
| Nextflow execution | `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` |
| Run-state persistence | `backend/lib/galaxy/ai/runs/` |
| QC gates / auto-loop | `qc_thresholds.json`, `cryosparc_qc_gates.py`, `backend/experiments/*autoloop*` |
| Autofix | `backend/lib/galaxy/ai/workflow_ops/autofix/`, `webapps/.../autofix3.py` |
| Billing | `backend/lib/galaxy/ai/billing/` |
| Memory / LTM | `backend/lib/galaxy/ai/memory/agentic_memory.py`, `frontend/server/memory-*.ts`, `frontend/shared/ltm-schema.ts` |
| Workflow catalog (.nf) | `backend/biomni_workflows/nextflow_nfcore/subworkflows/`, `backend/nf-core-modules/` |
| Deploy | `scripts/sync_to_dev.sh`, `deploy/`, `backend/Dockerfile`, `frontend/Dockerfile` |
| Connectors / MCP | `/Users/kky/biomate-connector` (separate repo), `.mcp.json` |
