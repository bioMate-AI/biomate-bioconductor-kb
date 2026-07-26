# Project Module — Performance Audit & Free/Premium Tier Proposal

**Date:** 2026-07-22
**Branch:** integration/next-phase
**Target:** https://dev-public.biomate.ai (live dev, fixture account, no mocking)
**Author:** session with kky

---

## Purpose

Continue testing the **project module**. Two deliverables:
1. A product-manager-level inventory of every element + a proposed **free vs. premium** split.
2. A **performance baseline** of the project module against live dev (API + browser).

The tier split is a **proposal pending decision** (kky deferred the call — see "Open Decisions").
The performance work is **done and reported below**.

---

## Part 1 — What the Project Module Is (PM element inventory)

Projects are a persistent workspace grouping **chats + files + workflow runs**, with a name,
description, `researchGoal`/instructions (injected into the LLM system prompt), tags, and a
3-tab detail page. Collaboration (share links, members, roles) is built and partly tested.

### Backend surface (`frontend/server/project-routes.ts`, 18 endpoints, all `authenticateToken`)

| Group | Endpoints |
|---|---|
| CRUD | `GET/POST /api/projects`, `GET/PATCH/DELETE /api/projects/:id`, `POST /:id/archive` |
| Sessions | `GET /:id/sessions` |
| Files | `GET /:id/files`, `POST /:id/files/upload` (≤500 MB → S3), `DELETE /:id/files/:fileId`, `GET /:id/files/:fileId/url` (presigned) |
| Members | `GET/POST /:id/members`, `PATCH/DELETE /:id/members/:memberId`, `DELETE /:id/members/me` (leave) |
| Sharing | `GET/POST/DELETE /:id/share-link`, **public** `GET /api/join/:token`, `POST /api/join/:token/accept` |
| Runs | `GET /api/workflows/runs?projectId=…`, `POST /api/workflows/runs/:runId/save-to-project` |

Policy: ownership/membership via `_isOwnerOrMember()`; **404 (never 403)** for non-members
(prevents enumeration). DB: `projects`, `project_members`, `project_share_tokens`,
`project_files`, plus LTM `project_knowledge/episodes/procedures`; `chat_sessions.project_id`
(ON DELETE SET NULL). Hard delete cascades; archive is soft (`status='archived'`).

### Frontend surface

- **`/projects`** (`pages/projects.tsx`) — search, sort (activity/created/name), status filter, grid of cards.
- **Project detail** (`pages/project-detail.tsx`) — Chat / Files / Workflow-Runs tabs; right sidebar with editable instructions, share panel, member list, details.
- **Create dialog** (`create-project-dialog.tsx`) — 8 templates + blank, name/description/instructions/category/tags.
- **`/join/:token`** (`join-project.tsx`) — public invite landing.
- Sidebar section, active-project banner, `active-project-context.tsx` (localStorage `biomate-active-project-id`).

### Existing test coverage
- **API/contract:** `project-routes.test.ts`, `project-framework-wiring.test.ts`, `chat-sessions-project-scoping.test.ts`.
- **E2E (Playwright):** `project-create`, `project-sharing` (PS1–8), `project-members` (PM1–6), `project-authz` (AUTHZ1–14), `project-files`, `project-workspace`, `project-team`, `conference-project-collab` (CC1–10, 10/10 on 2026-07-20).
- **Bash audit:** `scripts/audit_project_framework.sh` (S1 lifecycle, S2 validation, S3 isolation, S5 auth).
- **Known open gaps:** run-row click→viewer in Workflow Runs tab; full email-invite round-trip; no visual diff vs. reference design.

---

## Part 2 — Free/Premium Tier Proposal

### Critical finding: the module has **zero tier gating today**

`grep` of `project-routes.ts` for `tier / plan / free / pro / public / private / max-project / seat`
returns **nothing**. Every endpoint gates on ownership/membership only. A $0 free user gets
unlimited projects, unlimited members, share links, all 8 templates, and RBAC — **identical to a
Team user**. Meanwhile `frontend/PRICING_STRATEGY.md` already promises a split (Free = *public
workspace*, Pro = *private workspace*, Team = *shared workspaces + RBAC + analytics*). **Code and
pricing page disagree.** Any free/premium test plan must first pin the gates.

### Existing tiers (`PRICING_STRATEGY.md`)
Free $0 ($5 credits, 2 GB, public workspace) · Pro $20 ($30 credits, 20 GB, private workspace) ·
Team $40/seat ($60 credits, 100 GB, shared workspaces + RBAC + analytics) · Enterprise (custom, SSO/SAML).

### Proposed split — three monetization wedges

| Wedge | Boundary | Rationale |
|---|---|---|
| **1. Quantity** (Free→Pro) | Free = **3 active projects**; Pro+ = unlimited | Cheapest gate to build & test; organized researchers hit it fast |
| **2. Privacy** (Free→Pro) | Free = public/link-shareable; Pro+ = **private** | Strongest wedge for IP-sensitive pharma/biotech (unpublished data must be private) |
| **3. Collaboration** (Pro→Team) | Free/Pro = single-seat; Team = **invite members, editor/viewer roles, RBAC, team dashboard** | Classic per-seat expansion |

| Element | Free | Pro | Team+ |
|---|:--:|:--:|:--:|
| Create projects | ≤3 | ∞ | ∞ |
| 8 templates, LLM context, tags, rename, archive/delete, Files tab, Runs tab | ✅ | ✅ | ✅ |
| Storage per project | 2 GB | 20 GB | 100 GB/user |
| Private projects | ❌ | ✅ | ✅ |
| Share link (view-only) | ❌ | ▲ teaser? | ✅ |
| Invite members + editor/viewer roles + RBAC | ❌ | ❌ | ✅ |
| Team dashboard / usage analytics | ❌ | ❌ | ✅ |
| SSO/SAML, audit log | ❌ | ❌ | Enterprise |

Compute (runs) and storage are **already metered** by `quota-middleware.ts` + billing credits;
only **count, privacy, and seat** gates are net-new.

### Open Decisions (deferred by kky — needed before writing gate tests)
1. **Collaboration tier** — Team-only (recommended) vs. Pro+ vs. Free-gets-view-only.
2. **Free posture** — cap-count+allow-private (recommended) vs. public-only-uncapped vs. both.
3. **Plan scope** — spec-the-target/TDD (recommended) vs. test-current+document-gap vs. two-phase.

---

## Part 3 — Performance Results (DONE)

All probes: live dev, canonical fixture (`lifeifei163361@163.com`, tier `professional`), no mocking.
**100% 2xx across every sequential and concurrent probe. No 5xx, timeouts, or pool exhaustion.**

### 3a. Sequential API latency (15 iters; ~280 ms = network/TLS floor to us-west-2)

| Endpoint | med | p95 | max | note |
|---|--:|--:|--:|---|
| `GET /api/projects` (list) | 428 | 515 | 538 | heaviest read |
| `GET /:id` (+context) | 331 | 404 | 406 | ~4 parallel queries add ≈0 ms |
| `GET /:id/sessions` | 317 | 351 | 370 | |
| `GET /:id/files` | 330 | 463 | 739 | S3+DB, variance-prone |
| `GET /:id/members` | 318 | 343 | 358 | |
| `GET /workflows/runs?projectId` | 316 | 359 | 383 | |
| `PATCH /:id` | 321 | 360 | 364 | |
| `GET /join/:token` (public) | 312 | 357 | 359 | unauth path healthy |
| `POST /api/projects` (×10) | 320 | 401 | 401 | |
| `DELETE /:id` (×10) | 357 | **1366** | 1366 | cascade + S3, one outlier |

### 3b. Concurrency burst — `GET /api/projects`, 0 errors at every level

| concurrency | wall | p95 | errors |
|--:|--:|--:|--:|
| 5 | 517 ms | 516 | 0 |
| 10 | 914 ms | 912 | 0 |
| 20 | 880 ms | 851 | 0 |
| 40 | 1090 ms | 1083 | 0 |
| 20 mixed (list+detail+members+files) | 562 ms | 558 | 0 |

Latency scales ~linearly (single-region Node+Postgres), stays bounded, no degradation cliff.

### 3c. List-endpoint decomposition (latency vs. project count, 72→152)

```
GET /:id/members (1 query, no ensureLtmUser) = 316 ms   ← network+auth+1-query floor
list latency ≈ 413 ms + 0.71 ms/project      ← linear fit
```

| Component | Cost | Verdict |
|---|--:|---|
| Network + TLS + auth + 1 query | ~316 ms | Fixed RTT floor; dominates |
| `ensureLtmUser` upsert + `DISTINCT…EXISTS(project_members)` | **~97 ms** | Only real lever |
| Per-project scan + serialize | **0.71 ms/project** | Negligible (~1,000 projects → +0.7 s) |

`ensureLtmUser` (`project-routes.ts:121`) runs on **every** read though its own comment says it's a
day-1 one-time need — it's the ~20% overhead on list.

### 3d. Browser page-load (Chromium, Navigation Timing)

| Surface | FCP | load | content-ready | note |
|---|--:|--:|--:|---|
| `/projects` **cold** (first route) | 2.1–3.9 s | 1.8–3.7 s | first card 2.7–4.5 s | SPA app-shell bundle + hydration |
| `/projects` **warm** | **368 ms** | 248 ms | first card **1063 ms** | route itself is fast |
| project-detail (files tab) | 500 ms | 357 ms | tabs 1.1 s | |
| tab → chat | — | — | **85–101 ms** | client-side, snappy |
| tab → workflows | — | — | **38–43 ms** | client-side, snappy |

The 2–4 s cold FCP is the **app-shell** cost (whichever route loads first), **not**
project-module-specific — warm `/projects` paints in 368 ms. Warm first-card (1063 ms) − FCP
(368 ms) ≈ 700 ms = list API (~465 ms) + rendering **72 cards** (see 3e).

### 3e. Incidental finding — 72 stale projects on the fixture

Fixture holds **72 projects** (E2E debris; 2026-07-20 audit only cleaned `"BD Summit MG Demo*"`).
Not a perf bug, but inflates browser list-render and makes `/projects` look like a junk drawer in
demos. One-time cleanup by name prefix (`PERF *`, `E2E *`, `Test *`, `Sidebar Test`) recommended.

---

## Part 3.5 — Functional E2E (deep run, added after "perf-only was too shallow")

The Part 3 work measured **latency + status codes only** — it never verified behavior was
*correct*. This section runs the real functional suites against live dev.

### Fast functional suites — 59/59 PASS (74 s, no AWS Batch)

| Suite | Assertions | Result | Proves |
|---|--:|:--:|---|
| `project-authz` | 14 | ✅ | Member reads OK; member cannot PATCH/archive/delete/share (404); stranger 404; unauth 401 |
| `project-create` | 4 | ✅ | Create persists → appears in list; dialog; auth-gate |
| `project-members` | 6 | ✅ | Owner row; role-change rejections; owner-can't-leave (400); invalid role (400) |
| `project-sharing` | 10 | ✅ | Token lifecycle: generate→idempotent→public preview→accept→revoke→404 |
| `project-files` | 13 | ✅ | **Real S3 round-trip**: upload→tree→list→presigned URL→delete |
| `project-team` | 12 | ✅ | **Two real users**: share→register→accept→list→role viewer→editor→revoke→remove→leave |

### Heavy suites (real AWS Batch + LLM) — mixed

**`conference-project-collab` CC1–CC10 = 10/10 PASS** — incl. `researchGoal`→system-prompt (CC4),
**real ADMET AWS Batch run inside a project** (CC5), run→Workflow-Runs-tab linkage (CC6), GWAS chain (CC7).

**`project-workspace` = 1 flaky, 1 FAILED, 3 skipped** (suite is `describe.serial` → a failure skips the rest):
- UC-PW1 (researchGoal injection): **flaky** — failed on a transient `TypeError: Failed to fetch`, passed on retry.
- **UC-PW2 (upload → Analyze pre-fills chat): FAILED** — see root cause below.
- UC-PW3/4/5: **skipped** (unverified this run; PW4 rename & PW5 401 are independently covered by CC10 + authz).

### UC-PW2 root cause — spec / implementation / test three-way mismatch

Isolated probe (3× fresh projects, **0** fetch errors): **deterministic FAIL** — file uploads and
shows in the tree, but the chat input is **empty** after clicking "Analyze with BioMate".

Tracing the code:
- `project-detail.tsx:331 handleAnalyzeClick` builds a message from `projectFiles` and passes it via
  `openChatWithProject(undefined, msg)` → URL `/?q=<msg>`.
- `App.tsx:130` reads `?q=` into `initialMessage` (and strips the param).
- `chat-with-artifacts.tsx:493–507` — on `initialMessage`, calls `sender(initialMessage)`: it
  **AUTO-SENDS** the message. It does **not** put text in the input box.

So UC-PW2's assertion (`chatInput.inputValue()` contains the filename) **can never pass** against an
auto-send implementation — the input is empty *by design*. The 2026-07-09 roadmap **spec** said
"pre-fill the chat input"; the **implementation** auto-sends; the **test** asserts the spec. All three
disagree.

**FIX IMPLEMENTED (2026-07-22, pending deploy):** Product decision = **pre-fill-and-let-user-edit**
(scientific analysis needs user context — organism, design, comparison — before sending; auto-send
wastes an LLM turn). Change:
- `project-detail.tsx openChatWithProject`: Analyze navigates to `?draft=` instead of `?q=` (only the
  Analyze path uses `prefilledMessage`, so the marketing-hero `?q=` auto-send is untouched).
- `App.tsx`: reads `?draft=` into `initialDraft`, strips the param, passes to chat.
- `chat-with-artifacts.tsx`: on `initialDraft`, calls the existing `setChatDraft` (populates input,
  does NOT send). Guarded by `draftAppliedRef`; readiness via `senderReady`.
This makes UC-PW2's prefill assertion pass **as written** (input pre-filled with filename). Verified:
**tsc clean, vitest 944/0**.

**DEPLOYED + CONFIRMED (2026-07-22):** committed `8f846916`, synced to dev (frontend rebuilt, health +
smoke passed). Re-ran `project-workspace` on dev — the prefill is **confirmed working**:
```
[PW2] chat pre-filled: "I've uploaded these files to my project:
- e2e_test.fastq (263 B)
Please analyze these files and sug..."
```
The input now pre-fills with the filename **and size** (263 B) — which also confirms `projectFiles` is
populated at click time (the open question from the first run). The exact bug is fixed and live.

**UC-PW2 still fails DOWNSTREAM of the prefill** (not the fix): after submitting the generic message,
`Run button visible: false` — no workflow card. Two contributing factors: (1) **dev instability** —
pervasive `TypeError: Failed to fetch` / `net::ERR_FAILED` / 404s during the run (dev EC2 dropping API
calls all session; also flaked PW1); (2) a **test-design mismatch** — UC-PW2 expects a *generic*
"analyze these files" message to auto-route to a runnable workflow, but the whole point of
pre-fill-and-edit is that the **user adds scientific context before running**. The downstream behavior
is unchanged from the old auto-send code (same message text), so it is not a regression.
**Follow-up:** update UC-PW2 to reflect the new UX (prefill → append context → submit → expect run),
and re-run PW2–PW5 in a stable dev window. Do NOT burn more AWS Batch runs against an unstable dev.

**RESOLVED (2026-07-22) — `project-workspace` 5/5 GREEN.** After deploying the retry fix (§Part 3.5
Dev instability #1) and updating UC-PW2:
- UC-PW2 test changes (commits `d4432fd10`, `763644bd1`): (1) pre-fill-and-edit — append routing
  context after the prefill; (2) accept terminal state (completed OR failed) — synthetic FASTQ can't
  scientifically complete; (3) fixed two stale selectors that only surfaced once the test ran past
  prefill for the first time — `run-row-*` (was `project-runs-list`) and `workflow-artifact-panel`
  (was the React component name `nextflow-workflow-viewer`).
- Final dev run: **5/5 passed, 4.1 min, no flaky, zero retries.** UC-PW2 completed the full cycle:
  prefill → edited msg routes to `nf-core/rnaseq` → run → terminal `failed` (accepted) → run linked
  in project API → viewer renders → phase cards. **Zero `Failed to fetch`** this run (vs. retries +
  failures on every prior run) — the client-side retry doing its job.

Uploaded file `source='upload'` is confirmed and the `onFilesChanged` wiring exists, so the auto-sent
message *should* contain the filename — but **positive confirmation of the sent-message content is
pending**: dev EC2 became unstable mid-session (`Failed to fetch`, file-tree render timeouts across 3
probes), blocking the confirmation run. Re-verify in a stable dev window.

### Screenshot/output audit (2026-07-23) — findings the green tests hid
Visual audit of the E2E screenshots (not done initially — relied on pass/fail):
- **Verified correct:** file upload (263 B), metadata (names never "undefined", chat/run counts match),
  chat message + BioMate response (correct nf-core/rnaseq description, no hallucination), run→tab
  linkage, failed-run handling ("No outputs — run did not complete successfully", no stuck spinner),
  ADMET CC5 COMPLETED with real output table, notes synthesis (real markdown, correctly "Completed Runs: None").
- **`nf-core/rnaseq` launch crash — ROOT-CAUSED & FIXED.** The 07-22 screenshot read as `v3` but the
  variable is actually **`s3`** (low-res misread). The `log.exception` observability fix (`b9eb575a`,
  deployed) immediately captured the traceback from Galaxy's log file (`/app/galaxy.log`, not
  docker-logs stdout — that's why earlier searches were empty):
  ```
  _launch_bg → _execute_nextflow_impl → _validate_input_paths → _validate_s3_url:2276
  UnboundLocalError: local variable 's3' referenced before assignment
  ```
  **Root cause:** in `_validate_s3_url`, the boto3 `s3` client is created **only in the `else` branch**
  for non-public buckets. For a `_PUBLIC_REF_BUCKETS` bucket (`ngi-igenomes`, `broad-references`, …) the
  `if` branch does `pass`, so `s3` is never assigned — then `s3.head_object` at line 2276 raises. **nf-core/rnaseq
  pulls GRCh38 references from `ngi-igenomes`**, so any run with a specific object key in a public ref
  bucket crashes at launch. Reproduced live on 2026-07-23 (crashes at 20:33/20:35/20:37). **Fix:** skip
  the object-existence check for public ref buckets (already trusted; also avoids requester-pays/cross-region
  false 403s). Committed + deployed.
- **Notes-header overlap** — NOT a real bug. Only appears in the E2E browser where the Inter font is
  CORS-blocked (global `x-e2e-test-token` on the cross-origin font); JSX is clean vertical flow. A real
  user's browser renders it fine. (Couldn't screenshot with fonts because the SPA auth needs that same token.)
- **Stale probe projects** (`PROBE sent` ×2, `PROBE source check`) — my own leftovers; **cleaned up.**

### Teamwork/collaboration audit (2026-07-23) — roles are cosmetic + misleading UI
Deep test of the team feature (beyond the green TW1–12 lifecycle tests, which only checked role labels):
- **"editor" role grants NO capability (backend owner-only).** Live test: promoted a member to `editor`,
  then as that editor: `PATCH /api/projects/:id` (instructions) → **404**, `POST /files/upload` → **404**,
  `GET /files` → 200. Every content-mutating endpoint checks `existing.userId !== uid` (owner-only;
  `project-routes.ts:205,330,365`). An editor is read-only, **identical to a viewer**. The UI's Editor
  role + viewer↔editor dropdown promise edit rights that don't exist.
- **UI shows edit controls to read-only members.** A viewer/editor member's browser view (screenshotted)
  shows Upload, Edit-instructions, +tag, the ⋯ (rename/archive/delete) menu, and Analyze — all visible,
  all 404 on click. Only the share/invite panel is correctly `isOwner`-gated (`project-detail.tsx:817+`).
  Members DO correctly see the shared project (sidebar "SHARED" badge), owner's files, member list, "Leave project".
- **Net:** collaboration is view-only in practice but presented as fully editable.

**FIXED + VERIFIED (2026-07-26, commit `6c012935`) — "make editors real".** Backend: `_getUserRole`/
`_isOwnerOrEditor`; `GET /:id` returns `role`+`canEdit`; `PATCH` project, file upload, file delete now
allow owner OR editor (lifecycle/status, archive, delete-project, member mgmt, share links stay
owner-only; file delete is project-scoped). Frontend: edit-instructions/tags/upload/delete/dropzone
gated by `canEdit`; ⋯ actions menu stays owner-only — viewers get a clean read-only workspace. Deployed
healthy; live-verified: viewer PATCH/upload → 404; after promotion editor PATCH → 200, upload → 201,
edit persisted; editor status change → 403 (owner-only preserved). (Note: the fix was re-implemented
after the first uncommitted version was lost to a between-session working-tree reset — committed
immediately this time.)

### DB cascade integrity (audit S6) — VERIFIED (2026-07-23, read-only SSM)
Previously deferred (needs direct Postgres). Now closed via `docker exec biomate-dev-postgres psql`
over read-only SSM (all mutations via the API):
- **Schema proof** — FK `ON DELETE` rules on all children of `projects(id)`:
  `project_knowledge / project_episodes / project_procedures / project_members / project_share_tokens`
  = **CASCADE**; `chat_sessions / sessions / workflows / correction_log` = **SET NULL**. Exactly the
  design contract; Postgres enforces it atomically.
- **Behavioral proof** — created a project, notes-refresh wrote a `project_knowledge` row
  (before: `project=1, knowledge_rows=1`), API `DELETE` returned 200 (after: `project=0,
  knowledge_rows=0`). Hard delete, cascade fires, no orphans.

### Environmental note
Dev EC2 showed transient instability during this session (flaked PW1, blocked confirmation probes).
Not a project-module bug, but it means UC-PW2's *content* verification and PW3/4/5 remain open.

### Dev `Failed to fetch` — root cause (investigated 2026-07-22)
Read-only diagnostic investigation (SSM, nginx/Node/Galaxy logs, live `ps aux`, CloudWatch, empirical probe).
**Debunked the leading hypothesis** (gunicorn recycling) and found the real cause:

- **NOT gunicorn recycling.** Galaxy on dev now runs `--workers=4 --max_requests=3000 --max_requests_jitter=300 --preload` (live-verified; config changed 2026-06-17, `backend/config/galaxy.yml.docker:21-47`). **CLAUDE.md's run-state-persistence section ("workers:1, max_requests:1000, ~3min recycle") is STALE and should be corrected.**
- **NOT the backend at all.** `/api/projects` is served by the **Node frontend from Postgres** — Galaxy is never in that path. Containers: 0 restarts, no OOM, CPU ~15% avg on a `t3.xlarge` (unlimited CPU credits).
- **Root cause:** a **transient client↔EC2-public-IP network/TCP+TLS connection-establishment loss**. Empirical probe: 232 requests over 2.5 min — 229 steady at ~370 ms, then **3 consecutive 20 s timeouts (~60 s window), then instant recovery**. nginx logged **zero** entries for the probe's source IP during the gap (connections never arrived) while serving a *different* client IP normally in the same window. So the server was up; only that client's new connections were blackholed.
- **No cushion:** `dev-public.biomate.ai → 52.42.49.175` (EC2 public IP directly) — no ALB, no client-side retry — so any network blip surfaces as `TypeError: Failed to fetch`. A multi-minute Playwright run with continuous polling (`listProjects`, `ChatHistory pull`, active-project refresh) almost certainly hits one.
- **CORS/font error = confirmed red herring:** the harness sets `x-e2e-test-token` as a **global** header (`playwright.config.ts:43-45`, `e2e/_fixture-login.ts:97-101`), attached even to the cross-origin `fonts.gstatic.com` request → preflight rejected. Decorative-font only; zero effect on API drops; never happens for real users.

**Production risk: low-moderate** — real users don't fire hundreds of retry-less requests over minutes, but the single-instance/no-ALB/no-retry topology has no resilience to blips.

**Recommended fixes:**
1. **Client-side retry w/ backoff** — ✅ **DONE (2026-07-22).** New `client/src/lib/fetch-retry.ts`
   (`fetchWithRetry`): retries transient network errors on **idempotent methods only** (never a
   POST/PUT/DELETE — no double-submit), never on HTTP 4xx/5xx. Wired into `ApiClient.request`
   (`api.ts`) and `ChatHistoryService.pullFromBackend` (`chat-history.ts`) — covers all 3 observed
   failing callers (`listProjects`, `active-project refresh` via ApiClient; `pullFromBackend` direct).
   6 unit tests (`fetch-retry.test.ts`). tsc + vitest green (959/0).
2. **Correct CLAUDE.md** run-state-persistence section — ✅ **DONE.** Added a dated NOTE with the
   current `workers=4 / max_requests=3000` config and the real Failed-to-fetch cause.
3. **Scope `x-e2e-test-token` to same-origin** — ⛔ **DECLINED (not worth the risk).** The token is
   load-bearing: it gates auth, quota, AND **rate-limit** bypass (`auth-middleware.ts:114`,
   `quota-middleware.ts:22`, `rate-limit.ts:17`), and the app's own in-browser API calls pass through
   those middlewares — during heavy E2E polling they need it to avoid tripping rate limits. Removing
   the global header would break that; scoping it to exclude only the cross-origin font needs
   `page.route` (forbidden by the repo's no-interception rule) or self-hosting the Inter font
   (unrelated app change). The font-CORS error is confirmed harmless (decorative, never hits real
   users), so the cost/risk exceeds the cosmetic benefit.
4. **ALB/CloudFront** in front of the instance — the durable infra fix for the direct-public-IP
   fragility; deferred (larger infra change, and #1 covers the app-visible symptom).

---

## Part 4 — Proposal / Next Steps

### Verdict
The project module's **CRUD/authz/sharing/members/files/LLM-context/run-linkage layer is functionally
solid** — 69 functional assertions pass against live dev incl. a real Batch run in a project. **One
real defect found:** the Files→"Analyze" flow (UC-PW2) — spec/impl/test disagree on whether it
pre-fills or auto-sends; needs a product decision then alignment. Performance is healthy. Optional
levers by ROI:

1. **Skip `ensureLtmUser` on the read path** (`GET /api/projects`) — guard behind a cheap
   existence check or in-process "provisioned" cache. Expected **−~97 ms** on list (~20%). Lowest
   risk, highest ROI. *Prototype-and-measure offered.*
2. **Cold SPA FCP (2–4 s)** — app-wide code-splitting / route preload. Benefits every route, not
   just projects. Larger effort.
3. **Clean 72 stale fixture projects** — demo hygiene, not perf.

### Tier work (blocked on Open Decisions above)
Once the three decisions are made, the test plan becomes a 2-sided matrix per gate
(below-line = allowed, at-line = 402/upgrade-CTA) + downgrade behavior
(e.g., Team→Pro with shared projects: what happens to extra members?). Gates are net-new code, so
this is build-then-test, not test-only.

### Harnesses (saved for reruns)
- `scratchpad/perf_projects.py` — sequential per-endpoint latency
- `scratchpad/perf_concurrency.py` — concurrency burst
- `scratchpad/perf_list_profile.py` — list decomposition vs. project count
- Browser page-load probe was a temp `frontend/e2e/perf_pageload.mjs` (removed after run; recreate from Part 3d if needed)

### Selector reference (for future E2E)
`card-project-{id}`, `tab-project-{chat,files,workflows}`, `button-new-project-chat`,
`button-generate-share-link`, `input-share-link`, `input-share-email`, `select-share-role`,
`button-project-actions`, `button-add-tag`, `button-leave-project`, `active-project-banner`;
panel: `workflow-artifact-panel`, `button-run-workflow-panel`, `panel-run-again-cta`.
