# 02 · Frontend (React client + Express server)

**Verified 2026-08-29.** Source: `frontend/`. The package is a single ESM project (`name: rest-express`) bundling the React SPA, the Express server, and the Drizzle ORM layer.

---

## 1. Build & tooling

- **Dev:** `tsx server/index.ts` (server) + Vite dev middleware (`server/vite.ts`) for HMR.
- **Build:** `vite build` → `dist/public` (client) **and** `esbuild server/index.ts --bundle --format=esm --outdir=dist` (server). One process serves the built SPA + API.
- **Vite config** (`vite.config.ts`): root = `client/`, output `dist/public`; **`dedupe: ["react","react-dom"]` is load-bearing** (prevents a dual-React crash); aliases `@`→`client/src`, `@shared`→`shared`. Dev proxy `/api`→`localhost:8080` (dev-only; differs from the 5000/8081 host map — noted for stack bring-up).
- **TS:** ES2022, `moduleResolution: bundler`, `strict: true`, `jsx: react-jsx`, `noEmit`.
- **Pre-sync gate:** `npx tsc --noEmit -p .` then `npx vitest run` (see [TEST_PLAN](../09-testing/TEST_PLAN.md)).

## 2. Express server (`frontend/server/`, ~120 modules)

### 2.1 The two hotspots
- **`routes.ts` — 16,999 LOC.** `registerRoutes(app): Promise<Server>` (L1359) registers **308 route handlers** and imports the sub-registrars. Also exports `rewriteInteractiveToolUrl` (L102), `getUploadedFile` (L947).
- **`galaxy-assistant.ts` — 9,677 LOC.** The Node-side LLM chat/workflow-generation orchestrator: `class GalaxyAssistant` (L2565), `StreamToolCallFilter` (L1930), prompt builders `buildDomainCatalogBlock` (L683), `buildWorkflowRoutingBlock` (L1242), `groundInlineParameters` (L1120), `inferActionsFromType` (L1373), `DEFAULT_MODEL_CONFIG` (L318).

### 2.2 Other core modules

| File | LOC | Role |
|------|-----|------|
| `galaxy-api-proxy.ts` | 1405 | HTTP proxy to Galaxy backend; singleton `galaxyAPI` |
| `auth-service.ts` | 862 | JWT `register`/`login`/`generateToken`/`verifyToken` |
| `project-routes.ts` | 852 | `/api/projects*` (~22 endpoints) + join links |
| `storage.ts` | 809 | Drizzle data-access facade |
| `iterative-workflow-generator.ts` | 717 | Iterative workflow-stub generation |
| `stripe-service.ts` | 610 | Stripe subscription/checkout |
| `workflow-sse.ts` | 567 | SSE manager (§4) |
| `galaxy-state-poller.ts` | 489 | Polls Galaxy invocation state → events |
| `orchestrator.ts` | 422 | Chat/tool orchestration |
| `auth-middleware.ts` | 269 | `authenticateToken`, `optionalAuth`, E2E bypass |

Sub-registrars imported by `registerRoutes`: `registerProjectRoutes`, `registerNotesRoutes`, `registerEvidenceRoutes` (also exports `queryPubMed`/`queryOpenTargets`/`queryStringDb`), `registerRegulatoryTrainingRoutes`. Subdirs: `functions/` (alignment, differential, quality-control, quantification, variants), `jobs/` (executor, router, artifact-store, handlers), `lib/` (paramRules, paramSchema, schemaGroundedExtractor), `services/`.

### 2.3 API route groups (308 handlers, by prefix)

| Prefix | ~Count | Notes |
|--------|--------|-------|
| `/api/workflows` | 58 | Largest: execution, templates, chains, drafts, SSE |
| `/api/memory` | 27 | LTM |
| `/api/galaxy` | 24 | Galaxy proxy incl. SSE endpoint |
| `/api/auth` | 22 | register/login/logout/me/mfa/oauth |
| `/api/invocations` | 15 | Galaxy invocation status |
| `/api/ai_assistant` | 13 | `generate_workflow` (L6448), pilot, citations |
| `/api/instruments` | 9 | connectors |
| `/api/user`+`/api/users` | 15 | |
| `/api/payments` | 8 | Stripe |
| `/api/parameter-templates`, `/api/datasets` | 7 each | |
| `/api/chat` | 1 | **`/api/chat/stream`** (L5535) — main chat SSE |
| `/api/billing/*` | 1 | **Catch-all proxy** (`app.all`, L14783) → Galaxy Python. **Billing is NOT implemented in Node.** |
| `/api/code` | 1 | run_code |
| `/internal/*` | 2 | incl. `/internal/sse-inject` (Python→Node SSE bridge) |
| non-`/api` | — | `/interactive`, `/connectors`, `/tools`, `/healthz` |

## 3. React client (`frontend/client/src/`)

Entry `main.tsx` → `App.tsx` (wouter). **183 components** (169 excl. `.test.tsx`; 107 top-level), 36 pages, 10 hooks, 2 contexts, 42 lib modules, plus the flag-gated `v2/` tree (§3.5).

> **Which UI is live?** `App.tsx:194` renders the **v1** `components/` surface by default and the **v2** `ResearchApp` only when `useUiFlavor()==='v2'` — set by `?ui=v2` (URL param, persisted) or `localStorage.biomate_ui='v2'` (`hooks/use-ui-flavor.ts`). A designer/dev editing UI **must know which flavor they're looking at**: default = v1; `?ui=v2` = the parallel v2 tree. The two are mutually exclusive per render, not co-mounted.

### 3.1 Key components (v1 surface)

| Component | LOC | Purpose |
|-----------|-----|---------|
| `nextflow-workflow-viewer.tsx` | 3452 | Right-panel viewer: param strip, phase/step cards, QC gate, auto-loop, after-run tabs, live `data-status` |
| `chat-with-artifacts.tsx` | 2550 | Chat + right-panel layout container |
| `chat-interface.tsx` | 2285 | Message list + input orchestration |
| `workflow-artifact.tsx` | 1741 | Workflow artifact card / QC summary |
| `chat-message.tsx` | 1109 | Single message (markdown, wf-chip, disambiguation, alert banners) |
| `step-output-preview.tsx` | 916 | **Per-file preview dispatch** — decides `<img>` vs HTML table vs FASTA/VCF/text code-block per run output file (the CLAUDE.md step-output requirement lives here) |
| `execution-control-panel.tsx` | 762 | Run controls / QC profile selection (distinct from the viewer's own footer run button) |
| `qc-gate-modal.tsx` | 746 | QC blocking modal |
| `auto-loop-panel.tsx` | 590 | Remediation panel (was→now diffs) |
| `app-sidebar.tsx` | 558 | Left nav — actual entries: **New Chat, Workflows, Starred Workflows, Recent Tools, Connectors, IND Report, Billing, Settings**, plus chat-history status dots (blue=running/red=failed/green=completed). *(Not "Runs"/"CRO" — that was the stale CLAUDE.md spec.)* |

Subdirs: `ui/` (49 shadcn/Radix primitives), `viewers/` (11: structure-viewer, density-map-viewer, vcf-viewer, csv-table-viewer, sequence-viewer, fsc-curve-chart, ctf-quality-chart, motion-histogram-chart, annotation-viewer, interactive-tool-launcher), `settings/`, `feedback/`, `ind-report/`.

### 3.2 Pages (wouter routes)
Auth: `/login`, `/register`, `/join/:token`, `/forgot-password`, `/reset-password`, `/verify-email`, `/mfa-challenge`. Product: `/` (main chat), `/dashboard`, `/billing`, `/workspaces`, `/projects`(+`/:projectId/notes`), `/project-detail`, `/workflow/:id`, `/drug-discovery-cro`, `/ind-report`, `/capabilities`, `/debug/outputs/:runId`, `/debug/viewer/:runId`. Marketing: `/pricing`, `/blog`(+`/:slug`), `/about`, `/tutorials`, `/privacy`, `/terms`, `/checkout/:plan`.

### 3.3 Hooks & contexts
`useUnifiedExecution.ts` (primary SSE-driven execution state), `useWorkflowExecution.ts` (legacy SSE), `useWorkflowSync.ts`, `useRunAgainParamCarryover.ts`. Contexts: `auth-context.tsx` (client auth state, `/api/auth/me` on mount), `active-project-context.tsx`.

### 3.5 The `v2/` "ResearchApp" tree (flag-gated, live)
A parallel UI flavor — **not dead reference art**. It renders when `?ui=v2` / `localStorage.biomate_ui='v2'` (see §3 callout). Files: `ResearchApp.tsx`, `Chrome.tsx`, `ChatStream.tsx`, `ChatCards.tsx`, `WorkflowPanel.tsx`, `PhaseCard.tsx`, `AutoLoop.tsx`, `AfterRunReport.tsx` (the findings/after-run surface), `DisambigCard.tsx`, `PlanChecklist.tsx`, `Tour.tsx`, plus its **own** `sse-adapter.js` and CSS design tokens (scoped via `data-v2-ui`).

> ⚠️ **Parity gap (upgrade risk):** the CRITICAL live-`data-status` transition contract (§4) exists **only in the v1 viewer** — `grep data-status`: `nextflow-workflow-viewer.tsx` = 5, `v2/PhaseCard.tsx` = 0, `v2/WorkflowPanel.tsx` = 0. Findings rendering is also duplicated (v1 viewer tabs vs `v2/AfterRunReport.tsx`). Unifying the two trees — and porting the `data-status` contract + findings surface into v2 — is an open upgrade item. Don't promote v2 without closing this.

## 4. Real-time / SSE pipeline

```
Galaxy (Python) ──run──► galaxy-state-poller.ts ──events──► workflow-sse.ts ──SSE──► EventSource (client hooks)
                              (polls invocation)                (fan-out)
Python QC/progress ──POST /internal/sse-inject──► workflow-sse.injectRawEvent ──SSE──►
```

- `GalaxyStatePoller extends EventEmitter` (L36): `pollInvocation` (~2s, L148) → `detectStateChanges` (L193) emits `workflow_state` (L208), `step_state` (L246), `progress_milestone` (L315), `job_log` (L375).
- `WorkflowSSEManager`: `setupPollerListeners` (L106) bridges poller→clients; `sendEvent` (L395) formats `event:<type>\ndata:<JSON>\n\n`. Endpoints: `/api/galaxy/workflows/sse/:workflowId/:invocationId` (routes.ts:4355, ownership-verified) and `/api/workflows/:invocationId/events` (L4361, QC-gate stream). Python injects via `/internal/sse-inject` (L4468).
- Clients: `useUnifiedExecution.ts` opens the EventSource (L295), maps `workflow_state`→status, `step_state`→steps/progress, falls back to 3s polling if SSE unavailable. `v2/sse-adapter.js` consumes `chat_progress` for the ResearchApp chat stream.

### 4.1 What the user *sees* as events arrive (the live `data-status` contract)

The plumbing above exists to drive a **visible, real-time state machine** in the v1 viewer — this is the CRITICAL requirement in CLAUDE.md's UX-completeness + presentation standards. Each SSE event maps to a visible change:

| Run state | Overall badge `data-status` | Phase cards | Footer button | Findings tab |
|-----------|-----------------------------|-------------|---------------|--------------|
| **Pre-run (idle)** | `idle` | `pending` | "Confirm & Run" | — |
| **Running** | `running` (on `workflow_state`) | current phase flips `pending`→`running` (spinner) on `step_state`; steps flip `completed` | "Running…" (spinner) | "Analyzing outputs…" spinner |
| **Completed** | `completed` | all `completed` | "Run again" | summary + Key Results table + **Download report** button |
| **Failed** | `failed` (any phase `failed`) | offending phase `failed` | "Restart" | static "Analysis not available — workflow did not complete" (**no spinner, no polling**) |
| **QC-blocked** | gate alert (red border) | — | two-number **measured vs threshold** display in threshold colors; halt/advisory/pass coding | auto-loop was→now diff (red strikethrough → green new value) in `auto-loop-panel.tsx` |

The e2e test must observe **at least one idle→running→terminal transition in real time** (not mocked) — see [TEST_PLAN §1.2](../09-testing/TEST_PLAN.md). The QC-gate two-number display and the auto-loop was→now diff are BioMate's signature moat surfaces.

## 5. Client auth flow

JWT in an **httpOnly cookie `biomate_token`** (secret `JWT_SECRET`, bcrypt rounds=12).
- **Client** (`auth-context.tsx`): `login`/`register` POST with `credentials:'include'`; `checkAuth` GET `/api/auth/me` on mount; `mfaRequired`→`/mfa-challenge`.
- **Server** (`routes.ts:2111`): `authService.login` → `generateToken` → set cookie (`httpOnly`, `secure` in prod, `sameSite:'lax'`). Register sets a 7-day cookie; logout `clearCookie`.
- **Middleware** (`auth-middleware.ts`): `authenticateToken` (L50) checks per-user API key → `Authorization: Bearer` → cookie, in that order; subscription gate with the `X-E2E-Test-Token` bypass (default `biomate-e2e-bypass-token-dev-only`, non-prod only, **waives subscription check only — not identity**). `optionalAuth` (L219) is used by `/api/chat/stream`, `/api/ai_assistant/*`, `/api/billing/*`.
- **OAuth** (`oauth-service.ts`): passport Google + GitHub; **MFA** (`mfa-service.ts`): speakeasy TOTP + one-time recovery codes + JTI replay prevention.

Full server-side auth/credential detail: [AUTH_CREDENTIALS_SANDBOX](../06-billing-auth/AUTH_CREDENTIALS_SANDBOX.md).

## 6. Tests
E2E ~100 Playwright files (`e2e/*.e2e.ts` + `.demo.ts` + `.spec.ts`); vitest 35 server + 31 client suites (`vitest.config.ts`, jsdom). Enumerated in [TEST_PLAN](../09-testing/TEST_PLAN.md).
