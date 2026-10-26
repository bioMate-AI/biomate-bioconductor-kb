# Claude Design — Handoff Bundle (2026-10-25)

One entry point to every design reference. All paths are repo-relative; open them directly.
**Read order:** the **design-system spec** (§A) is the source of truth — start there. The
walkthroughs (§B) are worked examples of the spec in the real product UI. §E is the current
task (Problem 2). §F is net-new design work.

Canonical-version note: use **`reference/claude_design/tutorials_v2_enriched/`** as the
richest walkthrough set; fall back to base `reference/claude_design/tutorials/` only for the
items enriched lacks (d5–d7, s3). Ignore `webpage_design_v2/` for product work — it is the
marketing website, not the product UI.

---

## A. Design-system spec — the source of truth (15 files)

`reference/claude_design/data_centroid_design_v2/spec/` — the authoritative design system
(per "Design spec = source of truth"). Every product surface is specified here:

| # | File |
|---|---|
| 00 | `00 Foundations and the cold start.html` |
| 01 | `01 Search and evidence.html` |
| 02 | `02 Data analysis.html` |
| 03 | `03 Models.html` |
| 04 | `04 Files and the dataset object.html` |
| 05 | `05 Design and generate.html` |
| 06 | `06 The composer.html` |
| 07 | `07 The workflow panel.html` |
| 08 | `08 The full step view.html` |
| 09 | `09 Worked examples - search answers.html` |
| 10 | `10 Worked examples - model use cases.html` |
| 11 | `11 Design and generate - all modalities.html` |
| 12 | `12 Reports as editable files.html` |
| 13 | `13 Run cards by domain.html` |
| 14 | `14 Panes and output previews.html` |

---

## B. Product walkthroughs — worked examples (canonical: `tutorials_v2_enriched/`)

`reference/claude_design/tutorials_v2_enriched/*.html` (each EN + `.zh.html`):

- **Platform (t):** `t0-getting-started` · `t1-design-and-generate` · `t2-models-and-the-closed-loop` · `t3-run-and-report` · `t4-bringing-your-own-data`
- **Drug-dev (d/b):** `d1-qsar-classical-ml` · `d2-admet-deep-learning` · `d3-generative-lead-design` · `d4-binding-free-energy` · `drug-dev` (omnibus) · `b1-train-custom-model`
  - *Only in base `tutorials/`:* `d5-molecular-docking` · `d6-novelty-fto` · `d7-accelerated-stability`
- **Research / method (m):** `m1-search-and-evidence` · `m2-rnaseq-differential-expression` · `m3-accession-to-workflow`
- **Clinical / pharma (s):** `s1-noncompartmental-pk` · `s2-pbpk-simulation` · `s4-survival-analysis` (*`s3-ind-regulatory` only in base `tutorials/`*)
- **Benchmark / routing (rb):** `rb-boin` · `rb-param-prefill` · `rb-protocol-qc` · `rb-routing`
- **Instrument (HTML, the only one):** `qpcr-ddcq-walkthrough`

Also: **Research Agent UI** design — `reference/claude_design/research_agents/Research Agent UI.html`.

---

## C. Instrument-data workflows — "workflows of their data"

**HTML walkthroughs (NEW — the set to hand over):**
`reference/claude_design/instrument_walkthroughs/*.html` — **14 instrument demo walkthroughs**
in the same 8-scene format as the t/d/m/s series (title → problem → ideas → inputs → run →
result → trust → closing), each built from its manual with real `.nf` workflow names, file
formats, thresholds, and honest status verdict badges. Each result scene carries a
**`FIGURE SLOT — Claude Design`** placeholder (with the exact capture note) where real
screenshots slot. Files: `basespace-sequencing`, `somatic-tumor-sequencing`, `nanopore-minknow`,
`lcms-proteomics-metabolomics`, `advanced-proteomics-mass-spec`, `flow-cytometry-gating`,
`plate-reader-assays`, `cryoem-reconstruction`, `microscopy-pathology-imaging`,
`opentrons-liquid-handling`, `benchling-eln-lims`, `sila2-devices`, `sample-qc-instruments`
(+ the earlier `qpcr-ddcq` in `tutorials*/`). `basespace-sequencing` is the gold reference.

**Source content (what the walkthroughs were built from):**

- **Source of truth (real client inventory):** `docs/20260920_HOSPITAL_INSTRUMENT_RESOURCE_INVENTORY.md` — ~25 instruments → data outputs → path-verified workflow → honest status (✅/🟡/🆕/🔧). Backed by `docs/20260918_HOSPITAL_CORE_FACILITY_COVERAGE_TEST.md` + `..._FACILITY_WORKFLOW_AUDIT_AND_UPGRADES.md`.
- **Per-instrument manuals (14 EN + 14 zh):** `docs/user-manual/tutorials/instruments/*.md` (+ `.../zh/instruments/*.zh.md`) — basespace-sequencing, somatic-tumor-sequencing, nanopore-minknow, lcms-proteomics-metabolomics, advanced-proteomics-mass-spec, flow-cytometry-gating, qpcr-quantification, plate-reader-assays, cryoem-reconstruction, microscopy-pathology-imaging, opentrons-liquid-handling, benchling-eln-lims, sila2-devices, sample-qc-instruments.
- **Plan + coverage gaps:** `docs/20261008_INSTRUMENT_WORKFLOW_MANUALS_PLAN.md`.
- **Catalog types:** `INSTRUMENT_TYPES` in `frontend/shared/schema.ts:1565` (opentrons, minknow, epu, flow_cytometer, lcms, qpcr, plate_reader, sila2, basespace, benchling).

---

## D. Capability-area index (where each lives)

| Area | Primary references |
|---|---|
| **Loops (closed-loop)** | spec `03 Models`; walkthrough `t2-models-and-the-closed-loop`; auto-loop QC in d-series + `webpage_design_v2/blog-auto-qc-loop.html` |
| **Search** | spec `01 Search and evidence` + `09 Worked examples - search answers`; walkthrough `m1-search-and-evidence`; Research Agent UI |
| **Research workflows** | walkthroughs `m1/m2/m3`; spec `02 Data analysis` + `13 Run cards by domain` + `14 Panes and output previews`; Research Agent UI |
| **Target ID** | ⚠️ marketing only: `webpage_design_v2/target-identification.html` (+zh), `survey-target-identification.html`, 4 `blog-*target*`. No product UI (see §F). |
| **Instrument data** | §C |

---

## E. Current task — Problem 2: entity-aware findings + provenance

- **Framework / data contract (background):** `docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md`
- **Design brief (design against this):** `docs/20261025_PROBLEM2_FINDINGS_DESIGN_BRIEF.md` (regions, field→render map, states, acceptance examples, and the open questions for Design).
- **Spec files to focus on for this:** `07 The workflow panel`, `08 The full step view`, `12 Reports as editable files`, `13 Run cards by domain`, `14 Panes and output previews`.
- **Backend status:** the `FindingsDocument` contract + generic extractor are built and wired additively (field `findings_document`, not yet rendered) — the contract is a proposal pending Design's answers to the brief's open questions.
- Prior accepted decisions this builds on: `docs/20261024_CLAUDE_DESIGN_TAKEOVER.md`, `docs/20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`.

---

## F. Known gaps — net-new design work (no existing HTML)

1. ~~Instrument-data workflow walkthroughs~~ — **CLOSED (2026-10-25):** the 14-walkthrough HTML set is now built in `reference/claude_design/instrument_walkthroughs/` (§C). Remaining work is Design's: drop real screenshots into each `FIGURE SLOT` placeholder.
2. **Target-ID product UI** — the `target_id` system is built in code (identify_targets MCP tool), but only marketing/blog HTML exists; no product-UI design. Still net-new.

---

## How to use this bundle
Hand Claude Design this file. Everything is repo-relative and standalone HTML/markdown.
If Claude Design needs the files outside the repo, ask and I will physically bundle the
canonical set (§A spec + §B enriched walkthroughs + §C manuals + §E Problem-2 docs) into a
single folder.
