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
This makes UC-PW2 pass **as written** (input pre-filled with filename). Verified: **tsc clean, vitest
944/0**. Live browser confirmation pending deploy — local browser auth doesn't stick (redirects to
/login), and dev-public is the **live Boston BD Summit env (July 21–23)**, so deploy is held until
post-conference or explicit go-ahead. Then re-run `project-workspace` (confirms UC-PW2 + un-skips PW3/4/5).

Uploaded file `source='upload'` is confirmed and the `onFilesChanged` wiring exists, so the auto-sent
message *should* contain the filename — but **positive confirmation of the sent-message content is
pending**: dev EC2 became unstable mid-session (`Failed to fetch`, file-tree render timeouts across 3
probes), blocking the confirmation run. Re-verify in a stable dev window.

### Environmental note
Dev EC2 showed transient instability during this session (flaked PW1, blocked confirmation probes).
Not a project-module bug, but it means UC-PW2's *content* verification and PW3/4/5 remain open.

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
