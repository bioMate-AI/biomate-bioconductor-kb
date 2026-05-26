# IND Interface — Punch List Before Anything Else

**Date:** 2026-05-26
**Trigger:** User feedback — "There are so many invalid links, stubs, ill-placed audit window not following Claude design. Focus on finish your system first."
**Scope:** `/ind-report` page + every component under `frontend/client/src/components/ind-report/` + its CSS at `frontend/client/src/styles/ind-report.css`.

Audit grounded in the design reference: `reference/claude_design/IND_design/` (BioMate IND Report.html + ind/{Steps,DocPanel,Overlays,LeftNav}.jsx + ind/styles-ind.css).

This doc is the **work order**. Nothing else gets touched (no eval runs, no docs, no deploys) until this list is closed.

---

## P0 — must-fix before any external demo

### P0-1. TOTP sign is a stub (security illusion)
- **Where:** `IndOverlays.tsx::IndSignOverlay::doSign()`
- **Bug:** Any 6 digits unlock the Sign button. No TOTP validation, no second-factor check, no audit chain entry.
- **Fix:**
  - Wire to backend MFA: `POST /api/auth/mfa/verify` with the 6-digit code + user JWT.
  - On 200: also POST a new IND-specific signing endpoint that writes an append-only audit row (user_id, document_sha256, adapter_versions_used, timestamp, totp_validated:true).
  - On 4xx: red border on the TOTP boxes + "Code rejected — check your authenticator and try again."
- **Backend gap:** there's no `/api/ind-report/projects/:id/sign` endpoint yet. Need to add it next to the existing feedback routes in `feedback_router.py`.

### P0-2. Audit overlay positioned wrong (ill-placed)
- **Where:** `pages/ind-report.tsx:433` — `{showAudit && <IndAuditOverlay ... />}` is rendered at the **page root**.
- **Bug:** `.ind-audit-overlay` CSS is `position: absolute; inset: 0` — designed to overlay its positioned parent. The Claude design comment says explicitly `/* Audit overlay (right panel only) */`. At the page root with no positioned ancestor, the overlay floats relative to body and covers the entire viewport, not just the doc panel.
- **Fix:** Move the `{showAudit && <IndAuditOverlay …/>}` block **inside `<IndDocPanel>`** (or render via portal into `.ind-doc-panel`). The doc panel needs `position: relative` (verify in CSS).

### P0-3. Onboarding "New Chat" / "+" project button is a TODO
- **Where:** `pages/ind-report.tsx:393-395`
- **Bug:** `onNew={() => { /* TODO: wire new-project dialog */ }}` — clicking `+ New project` does nothing.
- **Fix:** Modal with: molecule name, target, indication, sponsor, regions multi-select. On submit → `POST /api/ind-report/projects` (endpoint exists). After 201, set activeId to the new project's id and close the modal.

### P0-4. Download → `alert("Download .docx (stub)")`
- **Where:** `pages/ind-report.tsx:335`
- **Bug:** Both Download Markdown and Download DOCX buttons fire `alert(…stub…)`.
- **Fix:**
  - `.md` path: server route that walks `DEMO_DOC_FOR_PANEL` (or real doc state), formats each section as `## §2.6.x` + body, returns `text/markdown` with `Content-Disposition: attachment; filename="<molecule>_§2.6.md"`.
  - `.docx` path: harder — needs `python-docx` on backend; for now, ship MD only and label DOCX "coming soon" (greyed out) rather than alert-stubbing.

### P0-5. Chat handoff → `alert("Chat handoff (stub)")`
- **Where:** `pages/ind-report.tsx:336`, `IndDocPanel.tsx:182` ("Open the campaign in BioMate chat").
- **Bug:** Alert popup.
- **Fix:** `navigate(/chat?context=ind-report&project=<id>&section=<active>)` — chat already exists at `/chat`, just pre-fills the project context so the customer can ask BioMate about a specific compound/section without losing where they were.

### P0-6. Floating doc FAB → `alert("Open document panel (narrow viewport stub)")`
- **Where:** `pages/ind-report.tsx:410-413`
- **Bug:** At ≤1024px viewport, the doc panel hides and this FAB appears — but clicking does nothing.
- **Fix:** Open the doc panel as a full-screen modal at that breakpoint. Add `.ind-doc-panel-mobile-modal` class that promotes it to `position:fixed; inset:0` and adds a close button.

---

## P1 — visible polish + stub removal

### P1-1. Sign overlay timer counts down forever
- **Where:** `IndOverlays.tsx:35` — `setInterval(() => setTimer(s => s > 0 ? s - 1 : 30), 1000)`
- **Bug:** Cosmetic countdown that never represents real TOTP window. Once it hits 0, jumps back to 30.
- **Fix (option A):** Compute real TOTP window from current time (RFC 6238 step = 30s, `Math.floor(Date.now() / 1000) % 30`).
- **Fix (option B):** Remove the timer entirely; just say "Use the 6-digit code from your authenticator app." Less impressive but not lying.

### P1-2. Audit dismissal saved but no UI feedback
- **Where:** `IndOverlays.tsx::submitDismiss`
- **Bug:** POST succeeds but the finding still shows as not-addressed until refresh.
- **Fix:** Optimistic update — mark `f.addressed = true` in local state on 200; show a small "Dismissed" badge.

### P1-3. Audit "Open" / "Jump to" doesn't smooth-scroll
- **Where:** `IndOverlays.tsx:287` — `onJumpTo(f.section)`.
- **Bug:** `el.scrollIntoView({block:"start"})` jumps abruptly; design uses smooth scroll.
- **Fix:** add `behavior: "smooth"`.

### P1-4. Region selector cosmetic-only
- **Where:** `IndDocPanel.tsx::region` state.
- **Bug:** Changing region (FDA/EMA/NMPA/PMDA) updates the dropdown but doesn't change the rendered prose. Customer expects different prose per region.
- **Fix:** Either:
  - Backend: `GET /api/ind-report/projects/:id/sections?region=EMA` returns region-tagged prose. Wire viewer to refetch on region change.
  - Demo state: keep one body but show a "Region: EMA — prose unchanged in demo; production refetches per-region drafts." disclaimer.

### P1-5. "12 SMILES uploaded · Edit" in Step 1 — Edit is a no-op
- **Where:** `IndSteps.tsx::Step1ProjectSetup:107`
- **Bug:** Inline "Edit" link calls `onEdit()` which the page handler maps to `setEditedParas` (paragraph-edit state) — wrong target, doesn't do anything visible for SMILES.
- **Fix:** Open a modal showing the 12 SMILES with delete/edit affordance. Or: greyed-out + label "Compound editing happens in BioMate chat."

### P1-6. NDA-number input in Step 1 is unused
- **Where:** `IndSteps.tsx:298` — `<input className="nda-input" placeholder="NDA #" />`
- **Bug:** Input renders but value isn't read or persisted.
- **Fix:** Either wire to `project.nda_number` field + PATCH endpoint, or remove the input entirely (Phase 1 IND doesn't have an NDA yet — feature was scoped wrong).

### P1-7. Tutorial button removed but tour state still mounted
- **Where:** `pages/ind-report.tsx:76` (comment), `data-tour="…"` attributes throughout.
- **Bug:** All components carry `data-tour="ind-step-1"` etc. but no tour library renders them. Dead markup.
- **Fix:** Either ship the tour (port `reference/claude_design/IND_design/ind/IndTour.jsx`) or strip the `data-tour` attributes. Don't keep dead hooks.

### P1-8. "Regenerate as is" radio doesn't actually do anything
- **Where:** `IndDocPanel.tsx::RegenerateModal`
- **Bug:** Two radio buttons: "Regenerate as is" vs "Regenerate with instruction". They're both `defaultChecked` based on `instruction` state, but clicking the radio doesn't change behavior — the submit just reads `instruction` either way.
- **Fix:** Either make the radios actually controlled (clear `instruction` when "as is" picked, focus textarea when "with instruction" picked), or replace with a single "Custom instruction (optional)" textarea.

---

## P2 — design fidelity / nice-to-have

### P2-1. Doc panel header hardcoded "BM-0042 · Acme Therapeutics · NSCLC"
- **Where:** `IndDocPanel.tsx:102`
- **Bug:** Doesn't use the active project. Even with BM-0038 selected, header reads BM-0042.
- **Fix:** `${activeProject.molecule} · ${activeProject.sponsor} · ${activeProject.indication}`.

### P2-2. SHA-256 prefix in doc footer is fake
- **Where:** `IndDocPanel.tsx:190` — `doc.shaPrefix`
- **Bug:** Hardcoded demo value, doesn't reflect the actual document hash.
- **Fix:** Compute SHA-256 of the canonical doc body client-side (`crypto.subtle.digest`) on mount + after each edit. Show first 12 chars.

### P2-3. "Discuss in chat" CTA references nonexistent chat-handoff flow
- **Where:** `IndDocPanel.tsx:180`
- **Bug:** Already covered by P0-5 — chat handoff is alert-stub.
- **Fix:** Same as P0-5.

### P2-4. Section tabs (§2.6.1 … §2.6.6) — coverage markers
- **Where:** `IndDocPanel.tsx:138`
- **Bug:** The little `<span className="marker">` next to each tab is supposed to color (full/partial/none) based on coverage, but all sections are hardcoded `coverage: "full"` in `DEMO_DOC_FOR_PANEL`.
- **Fix:** Compute coverage from actual `bodyByPid` keys — full when every required subsection has prose, partial when some are missing, none when zero.

### P2-5. EmptyState reference compound chips just close onboarding
- **Where:** `pages/ind-report.tsx:381` — `onPickReference={() => setShowOnboarding(false)}`
- **Bug:** Clicking Pembrolizumab/Osimertinib/Semaglutide just closes the empty state. The user expects: "load this as a starter project so I can see what a finished IND looks like."
- **Fix:** Pre-populate a project from `data/ind_demo/BM-0042/` etc when a reference is clicked.

### P2-6. Version history shows fake versions
- **Where:** `IndDocPanel.tsx::VersionHistory`
- **Bug:** Three hardcoded versions in the popover, no real version table.
- **Fix:** Need a backend version table (`POST /api/ind-report/projects/:id/snapshot` on Sign, `GET /api/ind-report/projects/:id/versions`). Defer if no time.

---

## Backend gaps surfaced by this audit

These are required to close P0-1, P0-3, P0-4, P1-4, P2-6:

| Endpoint | Purpose | Priority |
|---|---|---|
| `POST /api/ind-report/projects/:id/sign` | Two-factor signature; writes audit-chain row | **P0-1** |
| `POST /api/auth/mfa/verify` (already exists, needs to be called from sign overlay) | Validate TOTP code | **P0-1** |
| `POST /api/ind-report/projects/:id/sections/:secid/render` | Returns region-specific prose | **P1-4** |
| `GET /api/ind-report/projects/:id/document.md` | Markdown document download | **P0-4** |
| `POST /api/ind-report/projects/:id/snapshot` + `GET …/versions` | Version history | **P2-6** |

---

## What this audit deliberately does NOT cover

- The 5-model eval scaffold — paused per user instruction.
- vLLM provisioning — out of scope until the UI is finished.
- Mobile responsive deep-dive — narrow-viewport FAB stub is P0-6, the rest is P2+.
- Tour overlay (IndTour.jsx port) — P1-7 either ships it or strips it.

---

## Sequencing plan

Day 1 (P0):
1. Move audit overlay inside doc panel (P0-2) — 30 min, visual win
2. Wire `+ New project` modal (P0-3) — 1 hr
3. Markdown download endpoint + button (P0-4) — 1 hr
4. Chat handoff link (P0-5) — 15 min
5. Mobile FAB → modal (P0-6) — 30 min
6. TOTP sign — backend endpoint + frontend wiring (P0-1) — 2-3 hr; biggest item

Day 2 (P1):
7-12. The P1 items as listed.

Day 3+ (P2 + backend):
Depends on remaining time.

---

This list is the single source of truth for "the system isn't finished." Every item has a concrete fix. When all P0s close, that's "done enough to demo." When P0+P1 close, that's "done enough to ship to a paid pilot."
