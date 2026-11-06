# Phase-2 Re-Audit — Current System vs. claude_design v2

**Date:** 2026-09-18
**Branch audited:** `integration/dev-test` (all reads under `/Users/kky/biomate-review/`)
**Reference:** `reference/claude_design/data_centroid_design_v2/` — `dataui/*.jsx` authoritative over spec HTML
**Method:** four pinned surface-audits (results & trust, interaction & evidence, entry & collaboration, journey), each locked to the real tree with a `git rev-parse` self-check. Verified-present items were excluded from "gaps."

---

## The one finding that matters

**BioMate has already built the hard parts. Most of them are switched off.**

Every audit, independently, landed on the same root cause: the trust- and evidence-bearing
components a scientist needs — the versioned report, per-output SHA-256, the canonical output
resolver, the full **StepDetail** (provenance + params-it-actually-ran-with + rendered⇄raw
viewers), the rich **CitationPanel** (retrieval transparency, conflict surfacing, source reader),
the **CostEstimateBadge**, the quality-aware **DataChip** — **exist in the codebase but are
orphaned, commented out, or mounted only on a surface the user rarely reaches.**

The remaining work is overwhelmingly **wiring, not construction.** Several of the highest-trust
interactions in the entire design are **one unpassed prop** away from working. This matches the
standing pattern in this codebase: *the gap is wiring into the live path, not availability.*

That reframes the whole phase. We are not behind on building — we are behind on **connecting what
we built to where the user stands.** The plan below is ordered by that reality: the cheapest,
highest-trust wires first.

---

## Tier 1 — One-prop / one-wire quick wins (do first)

These are the best value-per-effort in the audit. Each reuses a fully-built component; the change
is small and the trust payoff is large.

> **Status (2026-09-18):** 1.1, 1.4, 1.5, 1.6 **shipped** (frontend, tsc + full unit suite green).
> 1.3 (cost) **decided: stays commented out** per product call — no runtime/cost badge on the
> pre-run panel. 1.2 (CitationPanel) **double-checked → decision: do NOT wire as-is** (see note
> under 1.2): the component is high quality but the live research path is data-starved, so wiring it
> today would add empty sections + dead export buttons. The honest, real win there is a small
> backend change (un-drop `abstract` + `relevance_score` at serialization), tracked separately.

### 1.1 Make findings numbers clickable → open the output they came from  `[HIGH]` — ✅ SHIPPED
- **Where:** `AfterRunReport.tsx:289` — `<FindingsCard>` is rendered **without `onOpenOutput`**.
- **Reality:** `linkifyFindings` + `onOpenOutput` are fully implemented in `findings-card.tsx`
  (96/225). The single most trust-building interaction in the design — *"where does this number
  come from?"* — is written and switched off by one missing prop.
- **Do:** pass `onOpenOutput` that opens the matching `source_file` in the Outputs preview (or the
  full step view, 1.4). **Highest value-per-effort item in this audit.**

### 1.2 The rich evidence UI (`CitationPanel`) — double-checked → **DO NOT wire as-is**  `[decision]`
- **What it is:** `citation-panel.tsx` (896 lines) — a genuinely high-quality, honest-by-design
  evidence renderer: "How this was searched" (per-source found·kept bars, "N of M kept"),
  `ConflictRow` ("sources disagree", never auto-resolved), `SourceReaderPane`, locus ("cited for:"),
  stated recency, per-citation APA/BibTeX copy + export, save-to-notes / make-instruction backed by
  the real project-knowledge endpoint. Retrieval/conflict sections only render with **real** data
  (filters on `Number.isFinite`; never fabricates "kept").
- **Why not wire it now (evidence, traced end-to-end):** the live research path is **data-starved**
  for this component. `research_agent.py` emits only title/authors/year/journal/doi/pmid; `abstract`
  + `relevance_score` are populated but **dropped** at serialization (`ai_assistant.py:5273-5282`);
  `locus`, `retrieval_date`, `corpus_version`, `formatted_apa/bibtex/short`, retrieval found/kept,
  and conflicts are **never** produced by the research path (formatted_* exist only for workflow
  *tool* citations). Wired today it would show the same 6 fields it shows now, plus honest-empty
  retrieval/conflict/recency sections and **dead** APA/BibTeX buttons (formatted_* empty). That is a
  lateral move with dead affordances — contrary to the honesty rule.
- **The real win instead (small, honest, tracked):** un-drop `abstract` + `relevance_score` at
  `ai_assistant.py:5273-5282` and surface a relevance badge + abstract in the current
  `ResearchResponseDisplay`. The full retrieval-transparency / conflict experience is a **backend
  feature** (track found/kept per source, detect conflicts, format citations) — a scoped task, not a
  Tier-1 wire.

### 1.3 Cost / runtime before Confirm & Run — **decided: stays off**  `[decision]`
- `CostEstimateBadge` (`nextflow-workflow-viewer.tsx:449`) is fully commented out and **stays that
  way** per product call: no runtime/cost badge on the pre-run panel (static estimates were
  inaccurate; cost belongs to billing). No action.

### 1.4 After-run outputs open the rich evidence viewer  `[HIGH]` — ✅ SHIPPED (1.4a)
- **Was:** `OutputsTab`'s bespoke lightbox handled only image/html/pdf/text; everything else showed
  "preview not available".
- **Shipped:** the lightbox body now mounts `StepOutputPreview`, which resolves the right viewer by
  file type — image/pdf/html/text **plus** structure (pdb/cif pLDDT·PAE), density maps (mrc/map),
  single-cell (h5ad/loom) + R-object launchers, sequence/annotation/VCF tracks, hit grids, and cryo
  JSON charts. It fetches the same `/api/workflows/runs/:id/step-file` endpoint the Outputs table
  already used (no new backend). `canPreview` widened so the "view" button appears for these types.
  Dead `TextFilePreview`/`TEXT_PREVIEW_EXTS` removed.
- **Deferred (1.4b):** "Open full step view" → `StepDetail` (param origins/provenance) needs the
  per-step param payload the after-run report doesn't currently carry — a separate backend/data task.

### 1.5 Re-run-from-here — ✅ SHIPPED (honesty fix)
- The `biomate:run-again-with-edits` handler in `chat-with-artifacts.tsx:447` is in fact **fully
  wired** (fetches the run, merges params, re-opens the panel, launches). The bug was only the two
  AfterRunReport buttons toasting "parent wire-up pending" — **stale, misleading copy**. Updated to
  "Re-running with your parameters — see the run panel."

### 1.6 Summary answers at a glance  `[HIGH]` — ✅ SHIPPED
- FindingsCard now renders a row of scannable **headline metric chips** (top key results) above the
  collapsed table; each chip with a known source is clickable (same open-output path as 1.1). The
  summary prose numbers are now clickable too (via 1.1).

---

## Tier 2 — Project surface (real construction; largest design gap)

The **project surface** is the least-built area against the design. `ProjectSetup.jsx` intends a
structured standing context; `project-detail.tsx` has a single free-text textarea.

### 2.1 Make the plan / hypothesis object usable  `[HIGH]`
- **Reality:** `project_plans` is **backend-only** — POST + GET-by-id exist (`project-routes.ts`
  L867–906), but there's **no list endpoint** and **no client reference** anywhere. The
  hypothesis→run thread dies in chat.
- **Do:** (a) add `GET /api/projects/:id/plans` (list); (b) add a small "Plan / hypothesis" card on
  `project-detail.tsx` (goal + hypothesis, "New plan", list); (c) chip each run with
  `basedOnPlanId` → plan. Lowest-effort path from stranded-backend to legible.

### 2.2 Split Notes from Instructions  `[HIGH — safety/trust]`
- **Reality:** one textarea labelled "Instructions" (`researchGoal`) is fed to the agent; no
  distinction between what the model reads and human-only notes. Users can't tell what the model
  acts on — the single biggest collaboration-safety clarity gap.
- **Do:** two blocks — **Standing instructions** (numbered, agent-read) and **Notes** (human-only,
  with "Promote to instruction ↑"). Keep `researchGoal` mapping for compatibility.

### 2.3 Standing-instruction list · output-requirement templates · per-project skills  `[HIGH]`
- **Reality:** all three from `ProjectSetup.jsx` are absent. Output templates (the after-run report
  is generated *to* them) and per-project experts (chemistry vs. clinical projects run different
  expert readings) don't exist; skill toggles live only in the global `ConnectorsDialog`
  (`biomate-active-skills`), not per-project.
- **Do:** build the numbered standing-instruction list, the output-requirement template card, and a
  per-project Skills & experts switch-list reading the account library ("none on yet" per §0.9.2).

---

## Tier 3 — Entry & honesty

### 3.1 Retire/replace the `/capabilities` marketing page  `[HIGH — honesty]`
- **Reality:** `pages/capabilities.tsx` is an off-spec marketing page — 9 job clusters listing raw
  pipeline names (`adc_design`, `protac_design`…), a "BioMate vs commercial software" price table,
  a "$1.5M+/year" claim. This is exactly the browsable-inventory-with-counts + lying-labels the
  spec forbids (§0.5, §0.9.1). The reference `Capabilities.jsx` is instead search-first, no-count.
- **Do:** replace with the search-first pattern (type-what-you-want, domain narrowing, "Ask in your
  own words", no counts, no price table) or route `/capabilities` → cold-start. At minimum delete
  the comparison table and named-workflow badge lists.

### 3.2 Cold-start fidelity  `[MED]`
- Router **"Start" button + normalized/canonical seed** (currently seeds raw typed text;
  `cold-start-dashboard.tsx` L580–628 shows lane+domain but no Start).
- **Thin launcher** for returning users (composer + 4 module pills + expand, session-remembered) —
  entirely missing; the full 4-card grid always renders.
- **Project-scope line** ("In *{project}* · its files and instructions are in context") — thread a
  `scope`/`project` prop into `ColdStartDashboard`.
- **Instant/Cloud tier note** (seconds/free-ish vs minutes-hours/billed) under the module grid.

### 3.3 Nav hygiene  `[MED]`
- Move **Connectors out of primary nav** into Settings & workspace (`app-sidebar.tsx` L251–262).
- **Strip descriptive subtitles** from nav rows (anchor-text rule §0.10: a nav item is a label and
  nothing else); move explanation to anchor text on the destination surface.

---

## Tier 4 — One-object-everywhere (consistency & navigability)

### 4.1 One shared quality-aware DataChip across all four call sites  `[P1]`
- **Reality:** the composer chip is a decorative blue icon + name; user-bubble attachments are dead
  text (`📎 name`); the file-tree row lacks a version tag. The design's `DataChip` carries a
  **quality dot + id@version + kind** and opens the same object everywhere.
- **Do:** one `DataChip` (quality dot via existing `QualityDot`/perception, name, `id@version`,
  kind) used in composer chips, user-bubble attachments, file-tree rows (add `v{n}`), and
  inputs-mapped rows. One component, four call sites → the object looks identical everywhere.

### 4.2 Quality + version on the dataset header; clickable lineage  `[P1]`
- Add QPill + version chip to the `dataset-object.tsx` header (currently behind tabs); make each
  Lineage run an "Open run" button, not static text.

### 4.3 Inputs-mapped card **with its reason** in the chat transcript  `[P1]`
- The binding + inferred reason is panel-only (`prerun-inputs-mapped`); the design's promise is that
  it travels **in the conversation**. Add a compact read-anchor mapping card to the assistant turn
  (reuse `deriveInputMappingRows`), each row a live DataChip + confidence/why pill.

### 4.4 Evidence-class badges on every output  `[MED]`
- Outputs key purely off file extension; add an `EvBadge` (perceptual/quantitative/symbolic/
  procedural) from the same resolver `StepOutputPreview` uses, so a file reads as *typed evidence*.

### 4.5 @-mention typeahead for inline file reference  `[P1]`
- Attaching data is a modal detour; add `@` typeahead in `chat-input.tsx` to reference a project
  file mid-sentence (keep the modal browser as the browse/preview fallback).

---

## Tier 5 — Polish

- **Legible, copyable checksums** — `ReproducibilityTab` truncates to 16 chars + tooltip; add
  copy-to-clipboard + algorithm label so a reviewer can actually `sha256sum -c`.
- **Save-evidence-answer as a versioned Files document, not a note** — `handleSaveToProject` writes
  a `notes_synthesis` knowledge row; route it to the Files/document path (versioned, openable) and
  show "Open in Files →".
- **Outputs search + per-output notes** in `OutputsTab`; consolidate the duplicate unversioned
  `workflow-report-viewer.tsx`.
- **In-panel dataset "Data mode" peek** (borrow-then-hand-back) instead of a full `/files` context
  switch from a run output.
- **Matched-domain chip** on the lane preview; **version compare/revert** in MethodsTab.

---

## What is credited as faithfully shipped (do not re-touch)

3-tab after-run report (Summary / Outputs / Reproducibility record); Summary "Run original"
immutable badge; real per-output SHA-256 + JSON download with honesty-gated chain-of-custody
wording; versioned `MethodsTab` report (`GET`/`POST /api/runs/:id/report/versions` + version list +
local-download fallback); download-all ZIP; canonical output resolver + IDOR-closed output access;
the full `StepDetail` (built, wired to the live phase view); `SkillsSelector`; clarify/typed-confirm
card (exceeds the reference via the `NONE` sentinel); lane override chip; progress/narration line;
composer deep-link + `/files?file=` shared-object backbone; data-hub `?file=` deep-link.

---

## Recommended sequencing

1. **Tier 1 in one pass** — six small wires, each independently shippable, each a visible
   trust/UX gain. Start with 1.1 (one prop) and 1.2/1.3 (un-orphan CitationPanel + CostEstimateBadge).
2. **Tier 2** — the project surface is the biggest true build; do 2.1 (plan object) first since the
   backend already exists, then 2.2 (Notes/Instructions split, safety-critical).
3. **Tier 3.1** (retire the marketing page) — honesty, do it early and cheaply.
4. **Tier 4** — the shared DataChip (4.1) unlocks 4.2–4.5 consistency.
5. **Tier 5** — polish, opportunistic.
