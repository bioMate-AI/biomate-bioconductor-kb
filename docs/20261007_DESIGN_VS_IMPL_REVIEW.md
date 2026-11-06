# BioMate — Design-vs-Implementation Review (missing / inconsistent functions)

**Date:** 2026-10-07. **Question:** does the product implement the *designed* functions, and is it
consistent with the design? **Method:** 4 parallel source-grounded reviews (entry flow, workflow panel,
after-run, shell+modules), each citing BOTH the design and the product source.

**Authority / ground truth (important):** the design is defined by
`reference/claude_design/data_centroid_design_v2/dataui/*.jsx` (the actual React shell:
`App.jsx`, `ColdStart.jsx`, `ChatView.jsx`, `RunSurface.jsx`), the `spec/*.html` pages, and
**`SIMPLIFICATION_DECISIONS.md`** — which explicitly **overrides** the minified
`BioMate Prototype (standalone).html` wherever they disagree. Several "gaps" the earlier pixel audit
implied are actually design-intended simplifications; those are marked ✅.

## Overall verdict
The implementation is **substantially faithful.** Confirmed as correctly built and consistent:
- **After-run = 3 tabs (Summary / Outputs / Reproducibility record)** with Methods/Parameters/Software/
  Citations/QC/Trajectory nested in the record tab — **exactly** the canonical design (not the prototype's 6 tabs). ✅
- Workflow panel: section tabs, QC-gate table (pass/advisory/halt + evidence tier + remediation diff),
  approval component, RolesCard/VerifyPattern, phase/step accordion, progress bar, pause/stop/run-again. ✅
- Entry flow: cold-start heading + intent bar, 4 module cards, lane+domain router (>6-char gate),
  lane preview + "why this?", project-suggestion row, Experts selector, file attach. ✅
- Shell: all nav destinations wired (Workflows/Connectors/Recent-Tools/Settings dialogs; Data/Models/
  Design/IND routes). ✅
- The product has **many legitimate extras** beyond the design (richer preview coverage, server lane
  arbiter, output-location picker, i18n, etc.) — these are fine, not defects.

Gaps are specific and fall into: **frontend-fixable**, **backend-dependent**, and **design-deferred
(product already handles honestly — track only).**

---

## MISSING — design specifies, product lacks

| # | Area | Item | Design ref | Product | Severity · class |
|---|------|------|-----------|---------|------------------|
| M1 | Shell | **Projects tree is flat** — no **Instructions** child, no inline **chat rows with status dots** inside each project, no per-project Runs/Models/IND | `App.jsx:187-195` | tree has only Chats/Files/Workflows; chats live in a flat Current/Recent list (`app-sidebar.tsx:334-427`) | **High · FE** |
| M2 | Shell | **Top-bar breadcrumb** (folder ▸ project ▸ new chat) | `ChatView.jsx:113-119` | absent (`chat-with-artifacts.tsx:1872-1887`) | **High · FE** |
| M3 | Panel | **Param-origin provenance under-wired** — only `autoFilled` is ever written; "Inherited" (design's most-emphasized origin), "Confirmed", "Edited" never set → dead code | taxonomy built `parameter-group.tsx:55-96`; design §7.4 | viewer writes only autoFilled (`viewer:310,362`) | **High · FE** |
| M4 | Entry | **Route-box "Start" that seeds a canonical/normalised goal** | `ColdStart.jsx:15-21`; spec 00 §0.5 | route box display-only; only raw-text send (`cold-start-dashboard.tsx:580-628`) | **High · FE** |
| M5 | After-run | **"Revert to v1" / restore a report version** | spec/12:41 | version list display-only, not clickable (`AfterRunReport.tsx:1385-1398`) | Med · FE |
| M6 | Shell | **IND Report** sidebar nav | `App.jsx:141` | commented out (`app-sidebar.tsx:266-272`) | Med · FE (route exists) |
| M7 | Shell | **"early access" footer tag** + **sidebar light/dark toggle** in the expanded footer | `App.jsx:202,472` | tag absent; ThemeToggle only in collapsed rail/public headers | Med · FE |
| M8 | Entry | Filed-project **"…its files and instructions are in context"** confirmation at cold start | spec 00 §0.4.4; `ColdStart.jsx:89` | `ColdStartDashboard` takes no project scope; only the *unfiled* suggestion exists (`chat-input.tsx:599`) | Med · FE |
| M9 | Entry | Models **"Run a model"** (pre-trained single-shot inference) track at cold start | `data-part3.js:178-182` | Models card is Train/Adapt/Optimise only; capability exists (`models/run-pretrained.tsx`) but unsurfaced | Med · FE |
| M10 | Panel | **Clarification / confirm-inference card** at top of Workflow-settings; **Fold/Show-workflow** control; pre-run **"Ready"** state word | RunSurface:191,175-178,157 | disambiguation only upstream in chat; no fold; idle hides status badge (`viewer:2618`) | Med · FE |
| M11 | Entry | Thin launcher + collapse/expand (returning-user compact mode); paste-a-URL ingest | spec 00 §0.4.3, spec 06 §6.1 | absent | Low · FE |

## INCONSISTENT — present but diverges

| # | Area | Item | Design | Product | Severity · class |
|---|------|------|--------|---------|------------------|
| I1 | After-run | **"Reproducibility bundle" ships the wrong bundle** | ONE honest bundle: report + every output + manifest + checksums (spec/12:34-37) | the button ships a *re-run* bundle (configs/scripts/logs/versions) (`AfterRunReport.tsx:1083-1090`) — naming + content mismatch | **High · FE/BE** |
| I2 | Panel | **Status vocabulary** never reads "Halted"/"Awaiting approval" | Ready/Running/Halted/Awaiting approval/Completed (RunSurface:157) | raw uppercase tStatus (`viewer:2606-2616`) | Med · FE |
| I3 | Entry | **Lane selector** | standing `Lane: auto ▾` (Ask/Compute/Workflow), always visible | binary override, visible only while typing (`lane-preview.tsx:234-252`) | Med · FE |
| I4 | Entry | **Instructions** | read-only **count chip** opening the standing project-instructions list | editable free-text textarea (`chat-input.tsx:641-682`) | Med · FE |
| I5 | Entry | **Experts popover** | "On in \<project\>" heading, per-pack default badges, "changed" marker on deviation | flat multi-select, no project framing/changed marker (`skills-selector.tsx:188-264`) | Med · FE |
| I6 | Shell | **Connectors elevated to primary nav** | belongs under **Settings & workspace connections**, not primary nav (SIMPLIFICATION_DECISIONS:52-53) | top-level nav item (`app-sidebar.tsx`) | Med · FE |
| I7 | Shell | Labels: per-project run child **"Workflows" vs "Runs"**; **"Settings & API Keys" vs "Settings & workspace"**; top-bar title **"New thread" vs "New chat"** | App.jsx | app-sidebar.tsx / chat-with-artifacts.tsx | Low · FE |
| I8 | After-run | Version chip on Summary beside the doc (design) vs only a "Run original" badge, version list buried in record (`:250-255,1385`) | spec/12:81 | — | Low · FE |
| I9 | After-run | Table preview lacks the **column-profile + rows×cols** shape header | spec/14:38 | `step-output-preview.tsx:277-305` | Low · FE |

## BACKEND-DEPENDENT (frontend is placeholder by design — need a backend trigger/API)
- **Human-approval gate** is a generic pre-run compute gate with a placeholder measured row; design §7.6
  wants action-specific what/why/cost/measured (publish/spend/overwrite/outward). Code notes no backend
  "awaiting approval" trigger exists (`viewer:2792-2812`).
- **Interactive Skip** (3-state toggles, per-phase Skip/Run-phase) is shipped read-only; interactive skip
  commented out pending a backend API (`viewer:963-969,3480-3516`).

## DESIGN-DEFERRED (product already handles honestly — TRACK, not defects)
Report **"In Files"** object, **edit-by-asking** (chat-propose-a-diff), **PDF/DOCX/HTML export** — all
design "retained / sequencing-TBD"; the product doesn't falsely claim them (`AfterRunReport.tsx:1243-1251,2143`).

## EXTRA (product-only — legitimate, keep)
Richer preview coverage (3Dmol/pLDDT, CryoEM FSC/motion/CTF, PAE, single-cell, RDS…), server lane
arbiter, output-location picker, folder/dataset/drag-drop attach + preview, run-again param carryover,
methods/QC-audit downloads, SHA-256 record JSON, streaming Stop, full i18n, onboarding, router self-test.

---

## Prioritized recommendation (frontend, quick-to-moderate)
1. **Wire param provenance** (M3) — write `inherited`/`confirmed`/`overridden` onto params so the existing
   badge taxonomy renders; this is the design's signature "resolved-with-origin" trust feature, currently dead.
2. **Projects tree** (M1) — add the Instructions child + inline chat rows with status dots (data already
   fetched in `app-sidebar.tsx`).
3. **Top-bar breadcrumb + "New chat" title** (M2, I7) — small, high-visibility.
4. **Fix the "Reproducibility bundle"** (I1) — either relabel the re-run bundle and add the real
   report+outputs+checksums verification bundle, or correct its contents. (Honesty-sensitive.)
5. **Status vocabulary** (I2) — map QC-halt → "Halted", approval → "Awaiting approval".
6. **Un-hide IND Report** (M6), add **early-access tag + footer theme toggle** (M7), **Lane standing
   selector** (I3), **Experts project framing** (I5), **Models "Run a model"** at cold start (M9).
7. Labels (I7), version-chip placement (I8), table shape header (I9), revert-to-v1 (M5), filed-project
   context line (M8), clarification/fold/ready (M10).
8. **Backend-dependent** (approval trigger, interactive skip) — needs API work first.

Raw per-area reviews (scratchpad): `rev_entry.md`, `rev_panel.md`, `rev_afterrun.md`, `rev_shell.md`.
Style/appearance companion: `docs/20261007_UI_STYLE_GAP_AUDIT.md` + `docs/20261007_BIOMATE_DESIGN_SYSTEM_GUIDE.md`.
