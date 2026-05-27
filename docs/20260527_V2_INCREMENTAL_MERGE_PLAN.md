# V2 Incremental Merge Plan

**Date:** 2026-05-27
**Owner:** yzhang
**Branch:** `integration/next-phase`
**Source sandbox:** `frontend/research_agent_v2/` (17 JSX files, Claude-Design handoff 2026-05-18)
**Target:** merge v2 frontend into the live BioMate app on `dev-public.biomate.ai` with no backend changes

---

## 1. Premise (verified, not assumed)

Backend is unchanged: v2 talks to the same `/api/workflows/execute` endpoint via the same SSE event vocabulary. The `sse-adapter.js` in the sandbox already exposes `connectRealBiomateStream(invocationId)` — no rewrite needed.

Frontend is the only delta. Audit summary:

| What v2 changes | Where (sandbox file) | Where it lands (current app) |
|---|---|---|
| Greeting + domain grid removed | `ResearchApp.jsx` | `chat-interface.tsx` |
| Sidebar simplified (Home / Workflows / Runs only) | `Chrome.jsx` | `app-sidebar.tsx` |
| Chat surface with speaker pills (PLAN/WF/QC/LOOP/AGENT/FIND) | `ChatStream.jsx` | `chat-with-artifacts.tsx` |
| Sticky checklist covering gen + exec phases | `PlanChecklist.jsx` | (new component) |
| 7-tab inline after-run report | `WorkflowPanel.jsx` (Findings · Outputs · Methods · Params · Software · Citations · QC audit) | `nextflow-workflow-viewer.tsx` |
| Phase cards with parallel glyph | `PhaseCard.jsx` | `nextflow-workflow-viewer.tsx` |
| Auto-loop remediation card | `AutoLoop.jsx` | `auto-loop-panel.tsx` |
| Pilot / comparison cards | `ChatCards.jsx`, `Modals.jsx` | `chat-message.tsx` |
| Drag resizer on right panel | `Chrome.jsx` | `chat-with-artifacts.tsx` |
| Rationale `(why?)` hover anchor | (anywhere) | (new utility) |

**Excluded from promotion** (per `research_agent_v2/README.md`):
- `ResearchTweaks.jsx` — Claude-Design preview tooling, not a product feature
- `data.js`, `research-data.js` — mock scenarios; replaced by real SSE stream

**Not addressed by v2 at all** (stay on current implementation):
- Auth pages (login, register, verify-email, reset-password, mfa-challenge)
- IND-report page
- CRO compliance page

---

## 2. Strategy: feature-flag + component-by-component

`useUiFlavor()` hook reads `localStorage.biomate_ui` and `?ui=` URL param; returns `'v1' | 'v2'`. Every v2 component is wired behind this flag so the live default stays `v1` until each surface is validated on dev.

Why not a single cutover:
- Many filename collisions (`WorkflowPanel.jsx`, `PhaseCard.jsx`, `Modals.jsx`, `Tour.jsx`, `Chrome.jsx`, `AutoLoop.jsx`) — co-locating risks silent import overwrites
- Workflow panel is the most integrated piece in the app (SSE, run-again, param override, QC alerts) — needs the longest validation tail
- Failing on one component shouldn't block shipping the others

Promotion path per component:
1. Land behind flag (default `v1`)
2. Dev-validate via `?ui=v2`
3. Flip default to `v2` for that surface; v1 path stays as escape hatch
4. After 1 week stable: delete v1 component

---

## 3. Phases

### Phase 0 — Foundation (½ day)

- [ ] Copy `frontend/research_agent_v2/src/*` → `frontend/client/src/v2/` (excluding `ResearchTweaks.jsx`, `data.js`, `research-data.js`)
- [ ] Namespace v2 CSS tokens: prefix `--v2-` on all custom properties in `tokens.css`, `research-tokens.css`, `layout.css`, `research-layout.css` so they don't clobber existing `--bm-*` tokens
- [ ] Add `useUiFlavor()` hook in `frontend/client/src/hooks/use-ui-flavor.ts`
- [ ] Wire `sse-adapter.js#connectRealBiomateStream` against the existing `/api/workflows/{invocationId}/events` endpoint (verify response shape matches)
- [ ] **Dev sync** — `/?ui=v2` should render `<ResearchApp />` at all (even if styling is off); `/` still serves v1 untouched

**Verification:** open `https://dev-public.biomate.ai/?ui=v2` → v2 chrome appears; `/` → v1 unchanged.

### Phase 1 — Quick wins (1 day, no v2 dependency)

These are the items from the todo that don't need v2 at all. Land them on dev first so the visible cleanup happens immediately.

- [ ] **#11** — remove `Good afternoon — welcome to BioMate` heading + 8-domain × 4-query grid from `chat-interface.tsx:395-401`
- [ ] **#17** — add Logout button to `app-sidebar.tsx` footer; wire to `POST /api/auth/logout` + `setLocation('/login')`
- [ ] **#21** — remove Settings / Billing / Help stubs from `IndLeftNav.tsx:73-79`
- [ ] **#14** — visually confirm CRO logo state; unify with platform if broken
- [ ] **#15, #18** — visually confirm CRO + IND top-right; source grep found nothing to remove, likely already-done

Ship as **one PR**, ~50-100 LOC. Sync to dev, hard-refresh, walk through every page.

### Phase 2 — Sidebar swap (1 day)

- [ ] Port `Chrome.jsx` sidebar markup into new `<V2Sidebar />` component under `frontend/client/src/v2/`
- [ ] Wire its nav items to the same routes as `app-sidebar.tsx`: Home → `/`, Workflows → starred-workflows dialog, Runs → `/dashboard` (when dashboard ships)
- [ ] In `App.tsx` chrome layout, `useUiFlavor() === 'v2' ? <V2Sidebar /> : <AppSidebar />`
- [ ] **Dev-validate** with `?ui=v2`; **flip default** after 1 day clean

**Risk:** low. Sidebar has few backend integrations (just navigation + logout).

### Phase 3 — Chat surface swap (2 days)

- [ ] Port `ChatStream.jsx` — keep speaker-pill rendering (PLAN / WF / QC / LOOP / AGENT / FIND)
- [ ] Port `PlanChecklist.jsx` — sticky checklist covering generation + execution phases
- [ ] Port `(why?)` rationale hover anchor as `<RationaleAnchor />` utility
- [ ] In `chat-with-artifacts.tsx`: `useUiFlavor() === 'v2' ? <V2ChatStream /> : <existing chat surface>`
- [ ] Reuse the same SSE subscription state — v2 components consume the same `chat_progress` event shape via `sse-adapter`
- [ ] **Dev-validate**, **flip default** after 1 day clean

**Risk:** medium. Need to preserve: message history persistence, run-status badges, workflow card injection after AI text, disambiguation card rendering.

### Phase 4 — Workflow panel swap (3 days, highest risk)

- [ ] Port `WorkflowPanel.jsx` + `PhaseCard.jsx` as `<V2WorkflowPanel />`
- [ ] Replicate all integration surfaces from `nextflow-workflow-viewer.tsx`:
  - SSE phase-card status updates (`data-status` attr)
  - "Run again" footer button → `POST /api/workflows/execute` with `runId` carryover
  - Param override modal → `GlobalParamsPanel`
  - QC gate alert + threshold editor
  - Auto-loop remediation card
  - "View phase outputs" link + inline file preview (img / table / FASTA / code)
- [ ] Port the 7-tab after-run report (Findings · Outputs · Methods · Params · Software · Citations · QC audit)
- [ ] In `chat-with-artifacts.tsx` right panel: `useUiFlavor() === 'v2' ? <V2WorkflowPanel /> : <NextflowWorkflowViewer />`
- [ ] **Dev-validate against all 6 scenarios from CLAUDE.md UX standard** (ADMET, RNA-seq, WGS, CryoEM, CRO compliance, drug discovery IND)
- [ ] **Flip default** only after each scenario passes a screenshot + assertion audit

**Risk:** highest. `nextflow-workflow-viewer.tsx` is the largest and most integrated component in the app. Allow 3+ days of validation before flipping default.

### Phase 5 — Polish components (1-2 days)

- [ ] Port `AutoLoop.jsx` — auto-loop card with parallel glyph + remediation diff
- [ ] Port `Modals.jsx` — pilot promotion modal, comparison modal
- [ ] Port `ChatCards.jsx` — pilot prompt card, comparison card
- [ ] Port drag-resizer from `Chrome.jsx` for the right panel
- [ ] Behind flag, validate, flip

**Risk:** low. These are leaf components with minimal integrations.

### Phase 6 — Default flip + cleanup (½ day)

- [ ] `useUiFlavor()` default → `'v2'` globally
- [ ] Keep v1 components live for 1 week as rollback escape (`?ui=v1`)
- [ ] After 1 week stable:
  - Delete `chat-interface.tsx` greeting/grid code
  - Delete legacy sidebar dialogs (StarredWorkflowsDialog can stay if v2 doesn't replace it; RecentToolsDialog can probably go)
  - Delete `nextflow-workflow-viewer.tsx`
  - Remove `useUiFlavor()` hook and all flag checks
  - Delete `frontend/research_agent_v2/` sandbox folder (no longer canonical)

---

## 4. Effort summary

| Phase | Duration | Risk | Daily dev visibility |
|---|---|---|---|
| 0 Foundation | ½ day | low | `/?ui=v2` renders at all |
| 1 Quick wins | 1 day | low | Greeting/grid gone, logout works, IND/CRO cleaned |
| 2 Sidebar swap | 1 day | low | New sidebar (behind flag) |
| 3 Chat surface | 2 days | medium | New chat surface (behind flag) |
| 4 Workflow panel | 3 days | **highest** | New after-run report (behind flag) |
| 5 Polish | 1-2 days | low | Auto-loop, modals, drag resizer |
| 6 Default flip | ½ day | low | v2 is default for everyone |

**Total: 9-10 dev-days**, spread over ~2 calendar weeks with validation tails between phases.

---

## 5. Rules / guardrails

- **No backend changes.** All v2 components consume existing `/api/...` endpoints. If a v2 component needs new backend data, stop and reconsider.
- **No raw v2 sandbox in production bundle.** Always copy + adapt into `frontend/client/src/v2/`; never reach into `frontend/research_agent_v2/` from app code.
- **Feature flag, never a fork.** Each phase keeps both v1 and v2 paths simultaneously. PRs that delete v1 only land in Phase 6.
- **One PR per phase, max.** Smaller PRs preferred. Never bundle multiple phases.
- **E2E tests preserved.** Every phase that swaps a surface adds a `?ui=v2` variant to the relevant Playwright spec; the v1 variant stays green until Phase 6.
- **No CSS-token clobbering.** All v2 CSS variables prefixed `--v2-` until Phase 6 deletes v1 styles.
- **Dev sync after every commit.** Per CLAUDE.md, every change is iteratively tested on `dev-public.biomate.ai` before being declared done.

---

## 6. Open questions

1. **Pilot workflow promotion** — v2 has `PilotPromptCard` + `PilotPromotionCard`. Does the backend pilot flow exist yet, or are these UI-only stubs?
2. **`/dashboard` route** — currently commented out in `App.tsx:346`. Should Phase 2 wire it (v2's Runs link expects it), or land Runs as a dialog like Starred Workflows?
3. **Auth in v2** — v2 has no auth pages. Confirm we keep current auth UI (just-fixed labels, logo, verify-email cookie) untouched through all phases.
4. **Tour engine** — v2 has `Tour.jsx` + `tour.css`. Is there interest in promoting the guided tour to production, or is it sandbox-only?

---

## 7. Out of scope

- IND-report page redesign (v2 doesn't address it)
- CRO compliance redesign (v2 doesn't address it; defer per bug doc until "fully validated")
- Workflow polish items #23-25 (weird phase index, "generating workflow" text, sample data) — separate workstream
- Workflow output viz / after-run panel gap assessment (#26-27) — separate assessment task
