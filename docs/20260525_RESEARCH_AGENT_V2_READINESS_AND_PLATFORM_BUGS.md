# Research Agent v2 Readiness & Platform Bug Tracker
**Date:** 2026-05-25  
**Author:** Claude Code audit  
**Branch:** integration/next-phase

---

## 0. Context

There are two separate concerns:

1. **Current platform bugs** — issues visible at `dev-public.biomate.ai` today (from `reference/05_25_todo.md`). Affect live users on the existing stack.
2. **Research Agent v2 promotion** — `frontend/research_agent_v2/` is a Claude-Design handoff (2026-05-18) that is the intended replacement UI. Currently an isolated sandbox with zero integration into BioMate. Not deployed anywhere.

The todo issues are against the *old* platform. v2 resolves many of them by redesign, but v2 is not promoted yet. Fix path:
- Auth/registration bugs (items 1–6): fix now in existing stack (affect live users regardless of v2 timeline)
- Everything else: resolve via v2 promotion, not by patching the old UI

---

## 1. Current Platform Bugs (fix in existing stack)

### BUG-01 · Register: "optional" label on required fields
**File:** `frontend/client/src/pages/auth/register.tsx:430`  
**Problem:** Role select has `(optional)` label text but the form *rejects* submission if blank (toast "Role required" at line 72–73). Institution field has same inconsistency. Confuses users.  
**Fix:** Remove the `(optional)` span from both fields, or make them truly optional.  
**Status:** Not fixed.

### BUG-02 · Register: "No payment required during trial" text
**File:** `frontend/client/src/pages/auth/register.tsx` trial step (line ~276+)  
**Problem:** Todo flags this text as needing removal. Needs visual confirmation on dev — grep didn't find the exact string but the page has a multi-step form and the text may appear in the trial step UI.  
**Fix:** Remove the "No payment required during trial" line if present.  
**Status:** Needs visual check on dev.

### BUG-03 · Register: Premium Plan price mismatch
**File:** `frontend/client/src/pages/auth/register.tsx:309`, `frontend/client/src/pages/pricing.tsx:36`  
**Problem:** Todo said $29 was shown instead of $49. Register now shows `$49 / month after trial` (line 309). Pricing page shows `monthly: 49`. Appears to be **already fixed**.  
**Fix:** Verify on dev visually; if confirmed fixed, close.  
**Status:** Likely fixed — verify on dev.

### BUG-04 · Register: Payment button goes to wrong page
**File:** `frontend/client/src/pages/auth/register.tsx:165–191`  
**Problem:** On success the start-trial call redirects to `window.location.href = '/'`. If Stripe session URL is returned (`data.url`), user goes to Stripe. On Stripe success/cancel, return URL is `${window.location.origin}/`. This should work, but todo says it goes to a page "which can not be opened" at `/dashboard`. May be an env issue on dev where `/dashboard` is gated and redirects back.  
**Fix:** Investigate on dev: does the Stripe return URL resolve correctly? Check if any post-payment redirect lands on `/dashboard` before auth state is set.  
**Status:** Needs investigation on dev.

### BUG-05 · Login: New user sign-in loops back to login page
**File:** `frontend/client/src/contexts/auth-context.tsx:125`  
**Problem:** After successful login the auth context calls `setLocation('/')`. For *newly registered* users (who went through the email-verify flow), the session cookie may not be set correctly before the redirect, causing the protected route to bounce them back to `/login`. This is likely a timing issue: the httpOnly `biomate_token` cookie from registration isn't being carried forward to the login call.  
**Fix:** Investigate the registration → email verify → login flow on dev. Check if the verify-email step issues a cookie or just a one-time token. Ensure login `/api/auth/login` is called (not skipped) after email verify.  
**Status:** Not fixed — root cause unconfirmed.

### BUG-06 · Email: Logo, button font, and links 404
**File:** `frontend/server/email-service.ts:28, 110, 119`  
**Problem (logo 404):** Logo loaded as `${this.appUrl}/biomate-logo.png`. `appUrl` defaults to `http://localhost:5000` if `APP_URL` env var is not set. On dev the public URL is `https://dev-public.biomate.ai` — if `APP_URL` is not set to that, email images and links point to localhost and 404.  
**Problem (button no font):** Button font is defined in a CSS `<style>` block (`font-family: Arial, sans-serif`), not as inline style. Many email clients (Gmail, Outlook) strip `<style>` blocks. Button renders with no declared font.  
**Problem (link 404):** Verify-email link is `${this.appUrl}/verify-email?token=...`. Same `APP_URL` issue. The route `/verify-email` exists in `App.tsx:298` but points to wrong host.  
**Fix:**  
1. Set `APP_URL=https://dev-public.biomate.ai` in dev EC2 env.  
2. Move button styles from CSS block to inline `style=""` attribute on the `<a>` tag.  
**Status:** Not fixed.

### BUG-07 · Footer: Copyright year
**File:** `frontend/client/src/components/site-footer.tsx:140`  
**Status:** **Already fixed** — shows `© 2026 BioMate Inc.`

### BUG-08 · Platform page: Greeting + domain grid
**File:** `frontend/client/src/components/chat-interface.tsx:395–401`  
**Problem:** "Good afternoon — welcome to BioMate" heading and 8-domain × 4-query grid are hardcoded and untested against live E2E flows.  
**Decision:** Do NOT patch this in the old UI. This is resolved by v2 promotion (v2 removes both). If v2 promotion is delayed, comment these out temporarily.  
**Status:** Deferred to v2 promotion.

### BUG-09 · Platform sidebar: No logout button
**File:** `frontend/client/src/components/app-sidebar.tsx:534–546`  
**Problem:** Bottom sidebar shows user name/email only. No logout action. Same missing in IND report and CRO pages.  
**Decision:** Fix in v2 promotion — v2 sidebar footer has user avatar but also needs logout added there.  
**Status:** Deferred to v2 promotion.

### BUG-10 · Platform sidebar: Billing widget + CRO Library link visible
**File:** `frontend/client/src/components/app-sidebar.tsx:172–235, 426–428`  
**Problem:** "Usage this month" billing widget is visible. CRO Library link navigates to an unfinished demo page.  
**Fix (immediate):** Comment out both sections.  
**Status:** Not fixed.

### BUG-11 · IND report: Multiple stub/broken UI elements
**File:** `frontend/client/src/pages/ind-report.tsx`  
**Problems:**  
- Hardcoded `jane@acme.com` avatar (line 81)  
- Tutorial button (line 76–77)  
- Settings/Billing/Help sidebar links are `<a href="#">` stubs (lines 68–80 of IndLeftNav)  
- "New project" button has empty TODO handler  
- Light switch + user account button in top right  
**Fix:** Comment out tutorial button, hardcoded email avatar, settings/billing/help links. Wire or comment out new project button.  
**Status:** Not fixed.

### BUG-12 · CRO compliance: Unfinished demo, still linked from sidebar
**File:** `frontend/client/src/pages/drug-discovery-cro-demo.tsx`, `app-sidebar.tsx:426–428`  
**Problem:** CRO page is a tabbed demo (`drug-discovery-cro-demo.tsx` — filename says "demo"). No sidebar matching platform format. No sample examples. The question of whether to rename or keep "CRO Compliance" is open.  
**Fix (immediate):** Comment out CRO Library link from sidebar (same as BUG-10). Defer full CRO work.  
**Status:** Not fixed (link still active).

---

## 2. Research Agent v2 — Readiness Assessment

### 2.1 What it is

`frontend/research_agent_v2/` — 9,173 lines of JSX + CSS, Claude-Design handoff 2026-05-18.  
**Not imported, not deployed, not reachable.** Runs as a standalone `index.html` with inline Babel.

17 source files split into: v1 panel components (extended), 5 new chat surfaces, demo data, tour engine, CSS tokens.

### 2.2 What it gets right (better than current platform)

| Area | Current platform | v2 sandbox |
|---|---|---|
| Greeting text | "Good afternoon — welcome to BioMate" | Removed — clean thread title only |
| Domain grid | 8 domains × 4 hardcoded queries | Removed — plain chat input |
| Sidebar items | Usage widget, CRO Library, Billing stubs | Home / Workflows / Runs only |
| Workflow progress chat | 🔹 italic lines only | Speaker pills: PLAN / WF / QC / LOOP / AGENT / FIND |
| Plan tracking | `TaskList` (generation only) | `PlanChecklist` — sticky, covers gen + exec phases with parallel glyph |
| After-run report | Scattered: methods-report download, QC modal | 7-tab inline panel: Findings / Outputs / Methods / Params / Software / Citations / QC audit |
| Run vs Run | No UI | `ComparisonCard` inline in chat |
| Pilot workflow | Plumbing exists, no UI | `PilotPromptCard` + `PilotPromotionCard` |
| Rationale | None | `(why?)` hover anchor on any chat line |
| Panel resizer | Fixed width | Drag handle |

### 2.3 What v2 does NOT have / is still mock-only

| Gap | Detail |
|---|---|
| **No auth pages** | Login, register, email-verify — not in v2 at all |
| **No IND report page** | Completely absent from v2 |
| **No CRO page** | Completely absent from v2 |
| **No logout button** | Sidebar footer shows user name but no logout action |
| **Tutorial button still present** | In `ChatColumn` header (same issue as current) |
| **All 5 surfaces run on mock tape engine** | `research-data.js` tape drives the demo. `sse-adapter.js` has `connectRealBiomateStream()` but it's wired to `?live=real` URL param, not the default |
| **PlanChecklist not wired to backend** | `TaskDecomposer.py` exists; React component not connected |
| **Speaker pills not wired** | Backend narrator emits events; `speaker` field not propagated to frontend render |
| **Rationale endpoint missing** | `/api/research/rationale/{phase_id}` doesn't exist |
| **ComparisonCard backend gap (WC-7)** | `storage.compareExecutionRuns` doesn't populate `parameterDifferences` |
| **Phase annotations in CryoEM** | `cryosparc_standard_spa/main.nf` has no `// [Phase X]` comments — panel can't group 23 steps |
| **After-run report backend** | Citations aggregator, findings generator per domain — not built |
| **Sample data suggestions** | Not in v2, not in current |

### 2.4 Promotion plan (from `docs/02_INTEGRATION_PLAN.md`)

Promotion is intentionally surface-by-surface. Locked scope decisions:
- Do NOT replace `chat-with-artifacts.tsx` wholesale — use `ResearchApp.jsx` as layout reference only
- Do NOT drop existing `TaskList`, real cancel/pause/resume, DeepAnalysisAgent, skip step/phase
- Do NOT import `research-data.js` tape into production (delete before any merge)
- Do NOT import `ResearchTweaks.jsx` (dev tool, not a product feature)

**Recommended promotion order:**

| Order | Surface | Files to port | Blocking backend work |
|---|---|---|---|
| 1 | Speaker pills on 🔹 lines | Extend `chat-message.tsx` with pill render from `ChatStream.jsx`; add 6 tokens to `tokens.css` | None — `speaker` field just needs to be forwarded by narrator |
| 2 | Plan checklist (sticky) | Merge `PlanChecklist.jsx` into existing `TaskList` | `TaskDecomposer` already emits tasks; wire plan-phase status updates |
| 3 | Panel resizer | Lift `.panel-resizer` CSS + `onResize` prop from `WorkflowPanel.jsx` into `nextflow-workflow-viewer.tsx` | None |
| 4 | (why?) rationale tooltip | Port from `ChatStream.jsx`; add `/api/research/rationale/{phase_id}` endpoint | New endpoint needed |
| 5 | Run vs Run comparison card | Port `ComparisonCard` from `ChatCards.jsx`; fix WC-7 gap in `storage.compareExecutionRuns` | `parameterDifferences` population |
| 6 | Pilot prompt + promotion | Port `PilotPromptCard` + `PilotPromotionCard` from `ChatCards.jsx` | 4 new `workflow.pilot_*` events from narrator |
| 7 | After-run report | Port `AfterRunReport` tabs from `Modals.jsx`; build citations aggregator + findings generator | Significant backend work per workflow domain |

### 2.5 Pre-promotion checklist (before any surface merge)

- [ ] `research-data.js` tape does NOT exist in production tree
- [ ] `ResearchTweaks.jsx` does NOT exist in production tree
- [ ] Feature flag exists (`BIOMATE_RESEARCH_AGENT_<SURFACE>=1`) for each surface
- [ ] Playwright suite passes for that surface against live backend
- [ ] Dev EC2 smoke test passes
- [ ] Existing chat-progress 🔹 lines, TaskList, cancel/pause/resume, DeepAnalysisAgent still work

---

## 3. What to do now (priority order)

### Immediate (fix in current stack, blocks live users)
1. **BUG-06** — Set `APP_URL` on dev EC2 + inline email button styles
2. **BUG-05** — Investigate and fix login loop for newly registered users
3. **BUG-04** — Verify payment button redirect on dev
4. **BUG-01** — Remove `(optional)` from required register fields
5. **BUG-10 + BUG-12** — Comment out billing widget and CRO Library link from sidebar

### Short-term (UX cleanup, not blocking)
6. **BUG-11** — Clean up IND report stubs (tutorial button, hardcoded email, Settings/Billing/Help links)
7. **BUG-02** — Confirm and remove "No payment required" text if still present

### v2 promotion (ordered by risk / value)
8. Surface 1: Speaker pills  
9. Surface 2: Plan checklist  
10. Surface 3: Panel resizer  
11. Surface 4: Rationale tooltip  
12. Surface 5: Run vs Run comparison  
13. Surface 6: Pilot cards  
14. Surface 7: After-run report  
