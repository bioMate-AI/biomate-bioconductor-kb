# Bench Prototype — Design Requirement

**Date:** 2026-06-19
**Audience:** Claude design agent at `localhost:7779`
**Format:** Standalone HTML prototype (same pattern as `reference/claude_design/cro/Workflow Panel Redesign.html`)
**Purpose:** Validate a new metaphor + voice direction for BioMate's UI *before* we commit to a codebase-wide rename. We need something to react to, not a finished design.

**Context for designer:** BioMate today reads as a competent internal tool that escaped — generic dev-tool aesthetics, mechanism-named features ("chain composer," "QC gate," "auto-loop"). A competitor (Deep Principle's *Mira*) recently shipped an upgrade that gets enormous mileage from (a) metaphor-based naming, (b) one coherent illustration system, and (c) verb-first voice. We want to inspire ourselves from their *craft*, not copy features. Full discussion in `docs/20260619_UI_INSPIRATION_FROM_MIRA_DISCUSSION.md` and `docs/20260619_MIRA_UPGRADE_COMPARISON.md`.

---

## The metaphor we want to test: The Lab Bench

A scientist's workspace. Drawer of reagents on the side, notebook open beside the bench, crew of collaborators leaning in, end-of-day write-up. Scales from solo PhD bench to multi-tenant CRO bench.

### Rename table (use these verbatim in mockup copy)

| Current term | Bench-metaphor term |
|---|---|
| Project | **Bench** |
| Project Library / files | **Drawer** |
| Chain / workflow | **Protocol** |
| Workflow run | **Run** (keep) |
| Chain composer | **Protocol designer** |
| Multi-agent / research agent | **Bench crew** (members: Lit-scout, Stats-reviewer, QC-checker, Methods-writer) |
| Auto-loop | **Re-run with adjustments** |
| QC gate | **Bench-check** |
| After-run findings | **Notebook entry** |
| Project memory / WIKI | **Lab notebook** |
| Methods report | **Write-up** |
| step-output-preview | **Pin to bench** |
| Skill / tool catalog | **Toolkit** |

### Voice — dual register

Every user-facing string should be presented in **two voices side-by-side** on at least one mockup screen so we can compare:

- **Warm voice** (for chat, empty-states, workflow cards, marketing): conversational, scientist-native, mechanism-free
- **Regulatory voice** (for IND/CRO reports, audit log, compliance surfaces): precise, citation-grounded, formal

**Example — same QC event:**
- Warm: *"Bench-check flagged hERG above 10 µM — that's the Aronov 2008 cardiac-safety line. Trying again with a tighter logP filter."*
- Regulatory: *"QC gate: hERG IC₅₀ exceeded 10 µM threshold (Aronov 2008). Remediation iteration 2 initiated with adjusted logP constraint."*

---

## 4 mockup screens required

### Screen 1 — Empty Bench (the landing / new-chat state)

**Goal:** the user understands what BioMate *is* in one glance, before they understand what it *does*.

**Today (what to replace):** chat empty state shows a list of suggestion chips ("Run RNA-seq," "Analyze ADMET"). Functional, forgettable.

**New direction:**
- A **scene illustration** of a bench (illustrated, not a screenshot). Visible elements: a notebook open on the bench, a drawer of files to one side, 2-3 stylized "crew" figures (the agents) standing nearby, a microscope or some lab object that grounds it in science. Style suggestion: warm pixel-art-ish or hand-drawn editorial — not corporate flat illustration. The illustration carries the metaphor.
- Three verb-first prompts woven into the scene (not chips in a row):
  - *"Ask the bench"* — opens chat
  - *"Open the drawer"* — opens project files
  - *"Review the notebook"* — opens last write-up
- One line of warm-voice copy under the headline: *"Your bench is ready. Tell me what you're investigating, drop a dataset on the drawer, or pick up where the notebook left off."*

### Screen 2 — Bench mid-run (active workflow)

**Goal:** while a run is happening, phases matter; the user wants to see progress.

**Today:** `nextflow-workflow-viewer.tsx` shows phase cards in a horizontal grid + step rows + footer button. Reads like a Jenkins CI pipeline.

**New direction:**
- Header: protocol name in **warm voice** ("RNA-seq protocol — Salmon → DESeq2 → enrichment, about 45 minutes on the cluster"). Note no `nf-core` or `AWS Batch` branding per existing rules.
- Phase strip: still horizontal but visually lighter — thin pill-row, not a stack of cards. Active phase highlighted; others muted.
- Below the phase strip: a **"crew working"** area — small avatars of which crew member is currently active (Stats-reviewer running DESeq2, etc). Borrows from Mira's pixel-office *idea* without being literal.
- Bench-check status pill — green / amber / red — with hover-text in warm voice
- Footer: single primary action (Pause / Re-run / View notebook depending on state)

### Screen 3 — Notebook entry (after run completes) — **the priority screen**

**Goal:** when a run finishes, the user should immediately see *the answer*, not a Download button.

**Today:** completed-run report is a markdown blob behind a Download button. Users don't know what just happened.

**New direction:**
- When run completes, this view **slides into the right panel automatically** (replacing the now-stale phase grid)
- Layout (top to bottom):
  - **Headline finding** — large type, one sentence. *"83% of compounds passed hERG bench-check; 17% flagged for cardiac risk."*
  - **Dataset summary** — small card: "120 compounds, SMILES + properties, 8 KB" (no S3 paths, no infrastructure leak)
  - **Key figures inline** — 1-2 plots / tables rendered, not linked-out
  - **Notebook entry body** — the methods + findings + citations in research-doc style we already ship
  - **Footer actions:** "Pin to bench" (keep this open while you start the next run), "Save a copy" (the old Download), "Run again with adjustments"
- Above the headline: a one-line *"Notebook entry · 2026-06-19 14:32 · Bench: ADMET Screening"* breadcrumb so it feels filed, not transient
- **Show this screen in both voices** — duplicate the headline area, one warm, one regulatory. This is the dual-register comparison.

### Screen 4 — Sidebar with Bench list

**Goal:** sidebar becomes a map of *your work*, not a menu of *features*.

**Today:** 9 items, all equally weighted (New Chat / Workflows / Runs / CRO Library / Starred / Recent / Billing / Settings / collapse).

**New direction:**
- **Top section: Your Benches** — list of projects, each showing:
  - Bench name
  - One-line status: *"3 runs in progress"* / *"notebook updated 2h ago"* / *"bench-check waiting on you"*
  - Tiny avatar cluster if shared
- **Middle: + New Bench** button
- **Bottom (demoted, smaller, grouped):** Toolkit, Billing, Settings
- "New Chat" is no longer a top-level action — chats happen *at* a bench. Surfaced as "+ Ask" inside each bench instead.

---

## What we explicitly do *not* want

- ❌ A direct copy of Mira's pixel-art office. Inspire from it; don't replicate.
- ❌ Whimsical illustration that undermines clinical/regulatory credibility. Warm but professional.
- ❌ Removing the regulatory voice anywhere. Dual register is the contract — IND/CRO users need precise language.
- ❌ A full Figma file or design system. This is a *prototype to react to* — HTML + Tailwind in the same style as existing `reference/claude_design/cro/*.html` is fine.
- ❌ Real working backend hookups. Static mockups only.
- ❌ Any reference to "nextflow" or "Galaxy" in user-visible strings (existing rule).

## Deliverables

1. `Bench-Prototype.html` — all 4 screens, single scrollable page with section anchors
2. One bench scene illustration (can be a placeholder SVG/PNG sketch if commissioning illustration is out of scope; mark clearly as placeholder if so)
3. A caption block under each screen listing the rename mappings used on that screen, so reviewer can see "this string in the mockup = this term in the codebase today"
4. A "What I changed and why" footer note (3-5 bullets) on choices the designer made that diverged from this brief

## How we'll judge it

After delivery we (user + me) will sit with the prototype and decide:
- Does the metaphor land, or does it feel forced?
- Does "Bench" work, or should we try Studio / Workstation / Notebook instead?
- Is dual register acceptable, or do we collapse to one voice?
- Which of the 4 screens is worth implementing first in the real codebase?
- Whether to commission the illustration system properly

**No code changes will be made to BioMate based on this prototype until we've reacted to it.** This is exploration, not specification.
