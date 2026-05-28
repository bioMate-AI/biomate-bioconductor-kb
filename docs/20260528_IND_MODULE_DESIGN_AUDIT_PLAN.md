# IND Module — Design Audit Plan + Test Matrix

**Date:** 2026-05-28
**Reference:** `reference/claude_design/IND_design/` (HTML + JSX + CSS)
**Demo fixtures:** `data/ind_demo/{BM-0042, BM-0038, BM-0029, README.md}`
**Existing tests:** `frontend/e2e/{ind-report-production, regenerate-dev-smoke, demo-11-ind-assembly}.e2e.ts`

This document is the test matrix used by `frontend/e2e/ind-design-audit.e2e.ts` (new). Every surface element from the Claude design is enumerated with: (a) expected behaviour from the reference, (b) current production behaviour, (c) verdict — match / minor deviation (acknowledged) / regression.

---

## Surfaces × demo states

The 3 demo projects in `data/ind_demo/registry/projects.json` correspond to the 3 main states the UI must render:

| Project | Status | Story | Drives test |
|---|---|---|---|
| BM-0042 | `in_progress` | Pipeline mid-flight — Step 3 PBPK running | Happy path / main shell |
| BM-0038 | `signed` | v3 signed 2026-05-09 | Signed-document state + version history |
| BM-0029 | `blocked` | 1 CRITICAL audit finding open | Audit overlay + CRITICAL severity styling |

Plus URL knobs already supported in `pages/ind-report.tsx::readKnobs`:
- `?onboarding=1` → EmptyState
- `?state=running` → Step 2 mid-progress
- `?state=pbpk-fail` → Step 3 fail state
- `?imported=1` → "imported from chat" banner on Step 2
- `?audit=critical` → CRITICAL audit injected

---

## Audit matrix

### A. Shell + LeftNav

| # | Element | Reference behaviour | Current | Verdict |
|---|---|---|---|---|
| A-1 | `.ind-shell` 3-col grid layout (LeftNav · Center · DocPanel) | grid-template-columns 240px 1fr 480px at ≥1280px | shipped via `styles/ind-report.css` | ⏳ visually verify |
| A-2 | Logo / app name | "BioMate IND" at top | shipped | ⏳ verify |
| A-3 | `+ New project` button | onNew → opens NewProjectModal | shipped (P0-3) | ⏳ test click |
| A-4 | Project list | 3 demo projects with status dot (running/signed/blocked) | shipped via `projects` state | ⏳ verify status dots |
| A-5 | Active project highlight | `.active` class on current row | shipped | ⏳ verify |
| A-6 | Settings cog | `onSettings` → opens settings overlay | shipped (minimal) | ⏳ verify |

### B. TopBar

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| B-1 | Breadcrumb "IND Report / <molecule> / §2.6 nonclinical" | yes | shipped | ⏳ verify text |
| B-2 | Region chips (FDA/EMA/NMPA/PMDA) | colored per region | shipped (chips render `activeProject.regions`) | ⏳ verify |
| B-3 | Tutorial button | yes | **explicitly commented out** ("no tour wired") | ✅ acknowledged omission |
| B-4 | User avatar (`jane@acme.com`) | yes | **explicitly commented out** ("hardcoded; replace with real auth") | ✅ acknowledged omission |
| B-5 | Active-adapter badge ("BioMate v6 — Customized for Acme") | shown when paid-tier | not yet wired | 🟡 TODO P3-ish |

### C. PipelineCenter — Step 1 Project Setup

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| C-1 | Step number "①" + title "Project Setup" + status pill "Complete" | yes | shipped | ⏳ verify |
| C-2 | Molecule / Target / Indication / Sponsor kv-list | yes | shipped | ⏳ verify per project |
| C-3 | Target regions toggles | yes; `on <region-lowercase>` class for active | shipped | ⏳ verify |
| C-4 | Compounds: "12 SMILES uploaded · Edit" | Edit opens compound list editor | shipped (P1-5) — opens SmilesListModal | ⏳ test modal |
| C-5 | Lead SMILES preview (monospace) | truncated SMILES with `…` | shipped | ⏳ verify |

### D. PipelineCenter — Step 2 ADMET

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| D-1 | Status pill "Complete" w/ pass count | "8/12 pass" | shipped | ⏳ verify |
| D-2 | Running state (`?state=running`) | progress bar + ETA | shipped | ⏳ verify |
| D-3 | Imported-from-chat banner (`?imported=1`) | purple banner with Re-run button | shipped | ⏳ verify |
| D-4 | Lead compound gates (hERG/DILI/Ames/Ro5) | colored ✓ chips | shipped | ⏳ verify |
| D-5 | Expand toggle → compound table | yes | shipped | ⏳ verify |
| D-6 | Wet-lab upload panel (PDF/CSV upload + NDA fetch) | yes | shipped, with NDA disabled (P1-6) | ✅ partial — acknowledged |

### E. PipelineCenter — Step 3 PBPK

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| E-1 | Status pill "Complete" + region chips (EMA ✓ FDA ✓) | yes | shipped | ⏳ verify |
| E-2 | Pass criterion box (green border + "EMA criterion met") | yes | shipped | ⏳ verify |
| E-3 | Failed state (`?state=pbpk-fail`) | red box + "criterion NOT met" + 2 action buttons | shipped | ⏳ verify |
| E-4 | Lead PK params row (f_u, Vd, t½, F) | mono-formatted | shipped | ⏳ verify |
| E-5 | Qualification table (expand) | yes | shipped | ⏳ verify |

### F. PipelineCenter — Step 4 Lead Selection

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| F-1 | Status pill: "Top: <compound-id>" with ✓ | yes | shipped | ⏳ verify |
| F-2 | Method + evaluated + rounds metadata | yes | shipped | ⏳ verify |
| F-3 | Top-5 ranking table | yes | shipped | ⏳ verify |
| F-4 | "Show all" expand | yes | shipped | ⏳ verify |

### G. PipelineCenter — Step 5 Document

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| G-1 | Audit summary chips per severity | yes | shipped | ⏳ verify |
| G-2 | "View Document" / Sign / Audit / Download buttons | yes | shipped | ⏳ verify |
| G-3 | Regenerate action | opens RegenerateModal | shipped (with SSE streaming) | ⏳ test |

### H. DocPanel header + tabs

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| H-1 | Title "CTD Module 2.6 — Nonclinical Written Summaries" | yes | shipped | ⏳ verify |
| H-2 | Version chip (e.g. `v2`) | clickable → version popover | shipped | ⏳ verify |
| H-3 | Sub-header `<molecule> · <sponsor> · <indication>` | dynamic | shipped (P2-1) — uses `headerSub` from active project | ⏳ verify per project |
| H-4 | Meta row: signed/not-yet-signed + region chips + date | yes | shipped | ⏳ verify both states |
| H-5 | Region selector dropdown | all 4 regions selectable | **EMA/NMPA/PMDA disabled (P1-4) with "coming soon"** | ✅ honest beta state |
| H-6 | Region note (NMPA: "incl. GLP declaration", etc.) | yes | replaced with "FDA-only in beta · multi-region coming soon" | ✅ honest |
| H-7 | Section tabs (§2.6.1–§2.6.6) with coverage markers | full / partial / none | shipped, **computed from real bodyByPid (P2-4)** | ⏳ verify markers |

### I. DocPanel body

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| I-1 | Section heading per section | yes | shipped | ⏳ verify |
| I-2 | Editable paragraphs (TipTap) | yes | shipped | ⏳ verify edit→captureEdit |
| I-3 | Inline audit chips (⚠ MAJOR, etc.) within paragraph text | yes | shipped | ⏳ verify chip render |
| I-4 | "+" citation popover button on hover | yes | shipped | ⏳ verify |
| I-5 | Regenerate button on each sub-paragraph | yes | shipped | ⏳ verify |
| I-6 | "💬 Discuss in chat" CTA at bottom | yes | shipped (P0-5) → routes to /chat | ⏳ verify route |

### J. DocPanel footer

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| J-1 | SHA-256 prefix display | fake hardcoded | **real SHA-256 of doc body (P2-2)** | ✅ improved over design |
| J-2 | "Generated by BioMate v1.0" line | yes | shipped | ⏳ verify |
| J-3 | "Requires human review" tag | yes | shipped | ⏳ verify |
| J-4 | Download Markdown / Download DOCX buttons | yes | MD works (P0-4); DOCX shows "coming soon" alert | ✅ partial — acknowledged |
| J-5 | Sign / Audit / Versions footer buttons | yes | shipped | ⏳ verify |

### K. Sign overlay (TOTP)

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| K-1 | Sign card with `Electronic Signature` title + 21 CFR Part 11 sub | yes | shipped | ⏳ verify |
| K-2 | Document card with molecule + SHA + char count | yes | shipped | ⏳ verify |
| K-3 | "Meaning of this signature" text | yes | shipped | ⏳ verify |
| K-4 | Reviewer credentials inputs (title/creds/scope) | yes | shipped | ⏳ verify editable |
| K-5 | 6-digit TOTP input + countdown timer | reference timer is cosmetic | **real RFC 6238 window (P1-1)** | ✅ improved |
| K-6 | "Sign and freeze" button | calls onSigned with stubbed values | **calls /api/sign endpoint with real validation (P0-1)** | ✅ improved |
| K-7 | Success card with real Sig ID + signed_at | reference uses fake `3f82a1cc…` | **real signature_id from backend response** | ✅ improved |
| K-8 | Error state on TOTP rejection | not in reference | added (P0-1 polish) | ✅ added |

### L. Audit overlay (inside DocPanel)

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| L-1 | Slides in from right inside doc panel | uses portal targeting `.ind-doc-panel` | **shipped via auditOverlay slot prop (P0-2)** | ✅ proper hosting |
| L-2 | "Regulatory Audit" title | yes | shipped | ⏳ verify |
| L-3 | Severity counter chips (CRITICAL/MAJOR/MINOR/INFO) | yes | shipped | ⏳ verify |
| L-4 | Severity filter dropdown | yes | shipped | ⏳ verify |
| L-5 | Finding card per item, severity-colored left border | yes | shipped | ⏳ verify |
| L-6 | "Jump to section" link with smooth-scroll | reference uses `block: start` (jumpy) | **smooth-scroll added (P0-2)** | ✅ improved |
| L-7 | Dismiss flow: 4 reason radios → backend POST | yes | shipped | ⏳ verify |
| L-8 | Optimistic UI on dismiss (fade + "Dismissed" badge) | not in reference | **added (P1-2)** | ✅ improved |
| L-9 | Footer with chain records + last verified | yes | shipped | ⏳ verify |

### M. Version history popover

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| M-1 | Opens on version chip click | yes | shipped | ⏳ verify |
| M-2 | Lists historical snapshots | reference is hardcoded v1/v2 fake | **real GET /versions (P2-6)** | ✅ improved |
| M-3 | "Current" badge with version number | yes | shipped (computed as latest+1) | ⏳ verify |
| M-4 | Each row: vN + Superseded + Signed + SHA + author | yes | shipped | ⏳ verify |
| M-5 | Loading / error / empty states | no | **added** | ✅ improved |

### N. EmptyState (onboarding)

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| N-1 | "Start a new IND project" CTA | yes | shipped | ⏳ verify |
| N-2 | 3 reference compound chips (Pembrolizumab / Osimertinib / Semaglutide) | clicking just closes onboarding | **clicking loads a demo project (P2-5)** | ✅ improved |
| N-3 | Reached via `?onboarding=1` knob | yes | shipped | ⏳ verify |

### O. Mobile FAB (≤1024px)

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| O-1 | Floating button shown when doc panel hidden | yes | shipped | ⏳ verify breakpoint |
| O-2 | Click opens full-screen doc modal | reference is non-functional | **shipped DocPanelMobileModal (P0-6)** | ✅ improved |

### P. SmilesListModal

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| P-1 | Opens from Step1 "Edit" link | reference is `onEdit={() => {}}` no-op | **shipped (P1-5)** | ✅ new feature |
| P-2 | List existing SMILES + lead radio | n/a | shipped | ⏳ verify |
| P-3 | Add row with validation | n/a | shipped (length/whitespace/atom-letter checks) | ⏳ verify validation |
| P-4 | Save returns entries to caller | n/a | shipped | ⏳ verify |

### Q. NewProjectModal

| # | Element | Reference | Current | Verdict |
|---|---|---|---|---|
| Q-1 | Opens from LeftNav `+ New project` | reference is TODO | **shipped (P0-3)** | ✅ |
| Q-2 | Fields: molecule/target/indication/sponsor/regions | yes | shipped | ⏳ verify |
| Q-3 | Posts to /api/ind-report/projects + selects new | yes | shipped | ⏳ verify e2e |

---

## What we explicitly do NOT match the reference on (and why)

| Item | Reason |
|---|---|
| Tutorial button (B-3) | No tour library wired; data-tour attributes stripped (P1-7). Re-add when an IndTour port exists. |
| User avatar `jane@acme.com` (B-4) | Hardcoded in reference; production needs real auth user. Commented-out placeholder until auth context is read. |
| Region cosmetic notes "incl. GLP declaration" / "ethnic bridging" (H-6) | Replaced with honest beta note. Misleading otherwise since selector is grayed. |
| DOCX download (J-4) | Reference doesn't implement either; we ship MD only and label DOCX "coming soon". |

---

## Test execution plan

The new `frontend/e2e/ind-design-audit.e2e.ts`:

1. Auth via setupTestUser
2. Walk each demo project (BM-0042 → BM-0038 → BM-0029)
3. Walk each URL knob (?onboarding=1, ?state=running, ?state=pbpk-fail, ?imported=1, ?audit=critical)
4. For each state: capture screenshots of LeftNav + TopBar + Center + DocPanel
5. Test interactions:
   - Click `+ New project` → modal opens
   - Click compound Edit link → SMILES modal opens
   - Click Audit button → overlay slides in from right side of doc panel
   - Click version chip → version popover opens with real backend data
   - Click Sign → TOTP overlay opens
   - Click Download MD → file downloads
   - Change region select → assert EMA/NMPA/PMDA options are disabled
6. Assert no `data-tour` attributes remain in the rendered DOM (P1-7 sanity)
7. Assert real SHA-256 in footer (not "(computing…)" or hardcoded shaPrefix)
8. Assert coverage markers vary per section (not all "full" hardcoded)

Total: ~20 surface checks × 3 projects × 5 knob combos = comprehensive coverage in ~3-4 min wall-clock.

Each screenshot lands in `/tmp/ind-design-audit/` with a stable name for visual diff.

Output of the run is a single console table summarizing match/deviation/regression per row of the matrix.
