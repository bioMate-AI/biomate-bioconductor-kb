# Tutorial Coverage Matrix — data-centric design vs. user-tutorial set

**Date:** 2026-10-02
**Author:** Yaoyun Zhang (coverage audit)
**Purpose:** Reconcile the full data-centric design (`reference/claude_design/data_centroid_design_v2/spec/00–14` + `dataui/*.jsx` prototype) against every existing and in-progress **user tutorial**, emit the authoritative tutorial inventory, and flag every design surface/function **not** covered so a second wave can close the gaps. Standard: *do not miss them* and *make sure each function really works* (so every gap is tagged known-working / untested / not-built — we do not write tutorials for vaporware).

> **Scope note — two different nav models.** The design spec (`data_centroid_design_v2`) is the *future* data-centric vision; its prototype sidebar is minimal (New chat · Workflows · Models · IND). The **shipping product** the tutorials actually describe has a fuller sidebar (New Chat · Workflows · Connectors · Data · Models · Design & Generate · Recent Tools · Projects · Settings & API Keys). This matrix audits **user-tutorial coverage of the design's user-facing functions**, grounded in what the shipping product actually exposes. Where the two diverge it is called out.

> **Explicitly out of scope (disabled in the current build — do NOT write tutorials):** Billing / Usage & subscription (spec/I13); **IND Report** generator (page exists but hidden from nav); **CRO Library / drug-discovery-CRO**; separate **Runs dashboard** (folded into Workflows). All four are confirmed switched-off in S1 §6 and in memory (billing/IND/CRO commented out intentionally due to a crash — do not propose restoring).

---

## 1. Authoritative tutorial inventory

### 1.1 User tutorials (the user-facing set — this is what the matrix scores)

| ID | File | Covers | Status |
|---|---|---|---|
| T0 | `tutorials/T0-getting-started.md` (+ zh) | What BioMate is; asking a first question in the composer; reading a first answer; honest day-one limits | **Exists** |
| T1 | `tutorials/T1-design-and-generate.md` (+ zh) | Design & Generate for **small molecules**: propose → score → rank; closed-loop intro | **Exists** |
| T2 | `tutorials/T2-models-and-the-closed-loop.md` (+ zh) | Models: browse/reuse a predictor; the wet-lab closed loop; how BioMate "gets smarter" | **Exists** |
| T3 | `tutorials/T3-running-a-workflow-and-reading-the-report.md` (+ zh) | Running a validated multi-step workflow; reading the after-run report; per-step input/output meaning | **Exists** |
| T4 | `tutorials/T4-bringing-your-own-data.md` (+ zh) | Ingest (file / URL / database); the dataset object; quality card; from-data-to-analysis | **Exists** |
| T5 | `tutorials/T5-viewing-your-results.md` (+ zh) | Opening a result; previews by type (figure/table/sequence/structure); good-vs-wrong output; save/share; interactive tools (RStudio/Jupyter/CellxGene) | **Exists** |
| T6 | `tutorials/T6-connecting-instruments.md` | Registering an instrument once; residency/status badges; acting on new-data events; the instrument **types** list | **Exists** |
| S1 | `tutorials/S1-sidebar-navigation.md` | Every sidebar entry top-to-bottom (New Chat, Workflows, Connectors, Data, Models, Design&Generate, Recent Tools, Projects, Chat history, Settings); collapse; "not available" list | **Exists** (appeared mid-audit) |
| M1 | `tutorials/M1-search-and-evidence.md` | Cold-start module **Search & evidence**: 4 tracks (Literature/Databases/Patents/Internal), cited answer surface, source reader, saved answers | **In progress** (sibling agent) |
| M2 | `tutorials/M2-data-analysis.md` | Cold-start module **Data analysis**: Instant ad-hoc compute vs. Cloud validated workflows, gear arbitration, domains & shapes, input resolution, skipping phases | **In progress** (sibling agent) |
| W1 | `tutorials/W1-workflow-panel-tabs.md` | Workflow panel tabs: Workflow settings · Phases · (After run); resolved params & origins; quality gate; approval; agent trajectory | **In progress** (sibling agent) |
| W2 | `tutorials/W2-after-run-panel.md` | After-run panel tabs: Summary · Outputs · Reproducibility record | **In progress** (sibling agent) |
| — | `tutorials/instruments/*.md` (×~10) | Per-instrument **analysis-workflow** tutorials (one per connector: Illumina BaseSpace, Nanopore MinKNOW, LC-MS, plate reader, qPCR, flow cytometer, Opentrons, cryo-EM, Benchling ELN, + generic/SiLA) | **In progress** (dir not yet created) |

Cold-start modules mapping (per task brief): **Search & evidence → M1**, **Data analysis → M2**, **Design & Generate → T1**, **Models → T2**.

Instrument connectors that back the `instruments/*.md` set (from `biomate-connector/lab_instruments/`): `illumina_basespace`, `nanopore_minknow`, `lcms`, `plate_reader`, `qpcr`, `flow_cytometer`, `opentrons`, `cryoem_instrument`, `benchling`, `sila2_adapter` (generic). That is 9 instrument connectors + 1 generic adapter ≈ the "10 per-instrument" set.

### 1.2 Developer module refs (NOT user tutorials — different audience)

`modules/I01–I14*.md` are 1:1 developer references against spec sections, not end-user tutorials. They are **not** counted as user coverage but are noted as the authoritative source a second-wave author should read.

| Dev ref | Spec | User-tutorial equivalent |
|---|---|---|
| I01 Cold start | 00 | T0 |
| I02 Composer | 06 | *(no dedicated user tutorial — partial in T0)* |
| I03 Search & evidence | 01/09 | M1 (in progress) |
| I04 Projects, instructions & collaboration | 00.14 / 06.5 | *(none)* |
| I05 Files & dataset object | 04 | T4 |
| I06 Running an analysis | 02/07 | T3 / M2 |
| I07 Full step view & provenance | 08 | *(none — partial in W1)* |
| I08 Outputs, viewers & interactive | 14 | T5 |
| I09 Reports & reproducibility | 07.8/12 | *(partial in T3 / W2)* |
| I10 Models | 03/10 | T2 |
| I11 Design & generate | 05/11 | T1 |
| I12 Connectors & skills | 00.9 | *(partial in S1 §4.3 / T6)* |
| I13 Billing | — | **excluded (disabled)** |
| I14 Instruments | 00.9 | T6 + instruments/* |

---

## 2. Coverage matrix — every design surface/function → tutorial

Legend: ✅ covered · 🟡 partial (overview only / folded into a broader tutorial) · ⏳ in-progress · ❌ MISSING · ⛔ excluded (disabled)

### 2.1 Foundations & cold start (spec 00, 01–05 entry)

| Design surface / function | Spec | Covered by | State |
|---|---|---|---|
| Cold-start view (4 module cards, 2×2 grid) | 00.4 | T0 + S1 | ✅ |
| Intent router / route box (lane chip + domain chip + Start) | 00.5 | T0 | 🟡 (basics only) |
| Thin launcher (returning-user compact view) | 00.4.3 | — | 🟡 (minor; not called out anywhere) |
| Two lanes (Instant vs Cloud) + lane arbitration | 00.3 | T0, T3, M2 ⏳ | 🟡 (named; dedicated "which lane & why" explainer thin) |
| Skills & experts as a **modifier** (composer toggles) | 00.6 | S1 §4.3, I12 (dev) | 🟡 (overview; no user how-to for toggling) |
| Workspace connections — overview | 00.8/00.9 | S1 §4.3 | 🟡 (overview) |
| Evidence classes & viewer resolution | 00.7 | T5 | ✅ |
| Domain viewers (structure+pLDDT, seq tracks, hit grid) | 00.7.1 / 03.8 / 05.5 | T5, T2, T1 | 🟡 (perceptual/table yes; domain-specific viewers thin) |
| Status vocabulary (Pending/Running/Done/Failed/Skipped/Halted) | 00.12 | T3, W1 ⏳ | ✅ |
| Verification-is-one-pattern (measured/threshold/verdict) | 00.13 | T3, W1 ⏳, T2 | ✅ |
| Roles & permissions (Viewer/Contributor/Reviewer/Owner; disabled-not-hidden) | 00.14 | — | ❌ |
| Resizable / collapsible panes | 00.11 / 14.1 | S1 (sidebar), T5 | 🟡 (sidebar only; chat/panel split uncovered) |

### 2.2 Search & evidence (spec 01, 09)

| Surface | Covered | State |
|---|---|---|
| 4 tracks (Literature/Databases/Patents/Internal); cited-answer surface; source reader; saved answers; typed questions | M1 ⏳ | ⏳ |

### 2.3 Data analysis (spec 02)

| Surface | Covered | State |
|---|---|---|
| Ad-hoc compute (Instant) vs. validated workflows (Cloud); gear arbitration | M2 ⏳ | ⏳ |
| Domains & workflow **shapes**; input resolution | M2 ⏳, T3 | ⏳ |
| **Skipping phases** / not-everything-is-skippable | 02.5 | M2 ⏳ (verify) / W1 ⏳ | 🟡 (confirm M2 or W1 includes it) |

### 2.4 Models (spec 03, 10)

| Surface | Covered | State |
|---|---|---|
| 4 tracks: Train / Adapt / Optimise / Run pre-trained | T2 | 🟡 (reuse/run covered; Train/Adapt/Optimise lighter) |
| Model object (versions, eval gate, lineage) | T2 | ✅ |
| Wet-lab loop (rounds, intake routes, mapping template, partial returns, refit) | T2 | ✅ |
| Bring-your-own-model (endpoint + residency + held-out eval) | 03.5 | — | ❌ (verify built before writing) |
| Domain inference viewers (structure prediction, genomic seq models, chemical screening) | 03.8 | T5, T2 | 🟡 |

### 2.5 Design & generate (spec 05, 11)

| Surface | Covered | State |
|---|---|---|
| 4 stages: Generate / Predict activity / Optimise / Rank; validity & safety gates; 2-view ranking | T1 | ✅ (small molecule) |
| **Other modalities** (protein / peptide / biologics) | 11 | — | ⛔/❌ — spec 11.6 says biologics is **thin / not fully built**; treat as **not-built**, do not write until shipped |

### 2.6 Files & the dataset object (spec 04)

| Surface | Covered | State |
|---|---|---|
| File tree / layout; ＋Add ingest | T4 | ✅ |
| Preview (Table / Columns / Plot / Edit) | T4, T5 | ✅ |
| Open-in (hand-off to viewers / Jupyter) | T4, T5 | ✅ |
| **Versions** (compare, restore, append-only, runs-that-read) | 04.4 | T4 | 🟡 (quality/preview strong; versioning deep-dive thin) |
| **Lineage / "where it came from"** (origin, quality-at-ingest, what-used-it/what-came-out) | 04.5 | T4 | 🟡 (origin+quality yes; lineage **navigation** thin) |
| **Access scope** (project / shared / account) | 04.2.3 | — | ❌ |

### 2.7 The composer (spec 06)

| Surface | Covered | State |
|---|---|---|
| Anatomy; attachments → data chip; lane preview | T0, T4 | 🟡 |
| Typed clarification card (parameter-bound) | 06.4 | T3, W1 ⏳ | 🟡 |
| Experts toggles & what they may not do | 06.5 | S1 | 🟡 |
| Post-run reply contract; mid-run narration cadence | 06.9 | T0, T3 | 🟡 |
| Filing-follows-intent; cross-lane handoff | 06.6.1/6.7 | — | 🟡 |

### 2.8 Workflow panel (spec 07)

| Surface | Covered | State |
|---|---|---|
| Panel structure; run-bar states; 3 tabs | W1 ⏳, T3 | ⏳ |
| Resolved parameters & their origins (default/inherited/recommended/confirmed/edited) | 07.4 | W1 ⏳ | ⏳ |
| Phases/steps + quality gate; override rule | 07.5 | W1 ⏳, T3 | ⏳ |
| Human approval gate | 07.6 | W1 ⏳ | ⏳ |
| Agent trajectory | 07.7 | W1 ⏳ | ⏳ |
| After run (Summary / Outputs / Reproducibility record) | 07.8 | W2 ⏳, T3 | ⏳ |

### 2.9 Full step view (spec 08)

| Surface | Covered | State |
|---|---|---|
| Step-as-object: provenance, resolved params, outputs rendered+raw, number→source, re-run-from-here | 08 | I07 (dev only) | ❌ (verify W1 doesn't absorb it) |

### 2.10 Reports & export (spec 12)

| Surface | Covered | State |
|---|---|---|
| Immutable run record; reproducibility download | 12.1/12.2 | T3, W2 ⏳ | 🟡 |
| **Editable project reports** (by hand / by asking); ask-to-edit diff | 12.3 | — | ❌ |
| **Export / download in 5 formats**; versions as one source of truth; project documents | 12.4–12.6 | — | ❌ |

### 2.11 Panes, previews & navigation (spec 14)

| Surface | Covered | State |
|---|---|---|
| Output/artefact previews by type | 14.2 | T5 | ✅ |
| Breadcrumb navigation across pages; consistency invariants | 14.3/14.4 | S1 | 🟡 |
| Collapsing the chat/run split; resizable panes | 14.1 | S1 (sidebar only) | 🟡 |

### 2.12 Run cards by domain (spec 13)

| Surface | Covered | State |
|---|---|---|
| Domain-specific run cards; what a card overrides; credentials; sandbox card | 13 | T3 (generic), instruments/* ⏳ | 🟡 |

### 2.13 Connectors / workspace connections (spec 00.9)

| Surface | Covered | State |
|---|---|---|
| Instruments (register, residency, events) | 00.9 | T6 + instruments/* ⏳ | ✅/⏳ |
| **Data sources** (directory index-in-place vs. copy-in; preview-before-attach) | 00.9.3 | T4 (ingest), S1 | 🟡 |
| **Databases** (connection + read scope; query+time origin) | 00.9.3 | T4, S1 | 🟡 |
| **MCP servers** (URL/auth + capability review) | 00.9 | S1, I12 (dev) | 🟡 |
| **Skills / experts** add-flow (declare needs/produces/residency) | 00.9.1 | S1, I12 (dev) | 🟡 |

### 2.14 Projects & instructions (spec 06.5, 00.9.2)

| Surface | Covered | State |
|---|---|---|
| Project instructions page (standing sentences + skill/expert switches) | 06.5/00.9.2 | S1 (mention), I04 (dev) | ❌ |
| Project scope, sharing, collaboration | 00.14 | I04 (dev) | ❌ |

---

## 3. Gap list — surfaces NOT covered by existing + in-progress tutorials

Ordered by priority. Each is tagged **known-working** / **untested** / **not-built** so the second wave does not document vaporware. Recommended filename + one-line scope given.

### P1 — real, shipped, user-visible, no tutorial

1. **Projects, instructions & collaboration** — `tutorials/T7-projects-and-collaboration.md`
   *Scope:* what a project is; the Instructions page (standing instructions **and** per-project skill/expert switches); sharing; the four roles (Viewer/Contributor/Reviewer/Owner) and "disabled-not-hidden" controls.
   *Spec:* 00.14, 00.9.2, 06.5. *Dev ref:* I04. *Status:* **known-working** (projects + instructions are live in product; roles exist). *Why it matters:* spec 00.9.2 makes the Instructions page the single place project behaviour is configured — currently only a passing S1 mention.

2. **Reports as editable files & export** — `tutorials/T8-reports-edit-and-export.md`
   *Scope:* immutable run record vs. editable project report; edit-by-hand and ask-to-edit (prose/cell diff); export/download formats; versions as one source of truth; project documents.
   *Spec:* 12. *Dev ref:* I09. *Status:* **known-working (verify)** — after-run report & DOCX export exist in product (IND DOCX narrative path exists), but the **IND Report** entry point is disabled, so anchor the tutorial on the generic report/export path, **not** IND. Confirm the "ask to edit a report" and 5-format export actually fire before writing.

3. **Connectors deep-dive: data sources, databases, MCP servers, skills/experts** — `tutorials/T9-connecting-data-and-tools.md`
   *Scope:* beyond instruments (T6) — add a directory (index-in-place vs copy-in), a database (read scope + query/time origin), an MCP server (URL/auth + capability review), a skill/expert (declare needs/produces/residency); preview-before-attach; residency badges.
   *Spec:* 00.9. *Dev ref:* I12. *Status:* **mixed** — directory/database ingest is **known-working** (T4 touches it); **MCP-server add** is **known-working** (biomate-connector ships an MCP server + capability manifest); **skill/expert add-flow** is **untested** from the end-user UI — verify the add-connector UI path exists before documenting that section.

### P2 — real surface, only partially folded into a broader tutorial; confirm then decide split-vs-extend

4. **Full step view & provenance** — extend W1, or `tutorials/W3-full-step-view.md`
   *Scope:* one step as an object — provenance, resolved params, outputs rendered+raw, **number→source** linking, re-run-from-here.
   *Spec:* 08. *Dev ref:* I07. *Status:* **known-working**. *Action:* check whether W1 (in progress) absorbs the full step view; if not, this is a standalone gap.

5. **Dataset-object deep-dive: versioning, lineage navigation, access scope** — extend T4, or `tutorials/T4b-dataset-versions-and-lineage.md`
   *Scope:* versions (compare/restore/append-only, runs-that-pinned-which-version); lineage navigation (what-used-it → what-came-out); scope project/shared/account.
   *Spec:* 04.2.3/04.4/04.5. *Status:* **known-working**. *Action:* T4 covers ingest+quality strongly but is thin on versioning/lineage/scope — extend T4 or add a focused companion.

6. **The composer in depth (lanes, clarification, experts, narration)** — extend T0, or `tutorials/T10-the-composer.md`
   *Scope:* lane preview & switching; typed clarification cards; expert toggles (and what they may not change — never a parameter); post-run reply + mid-run narration.
   *Spec:* 06. *Dev ref:* I02. *Status:* **known-working**. *Action:* likely an extension of T0 rather than a new file, unless M1/M2 leave it thin.

### P3 — lower priority / minor / confirm-only

7. **Models — Train / Adapt / Optimise tracks** — extend T2. T2 covers browse/reuse + wet-lab loop well; the three *authoring* tracks are lighter. *Status:* **known-working (verify training path end-to-end before deep docs).**

8. **Domain inference viewers** (structure+pLDDT chart, genomic score tracks, chemical screening hit grid) — extend T5/T2. *Spec:* 03.8/05.5. *Status:* **untested** per-viewer — confirm each renders in product before promising it.

9. **Chat/run-panel split collapse & pane resizing** — extend S1 or T5. *Spec:* 14.1. *Status:* **known-working** (UI behaviour). Minor.

### Explicitly NOT gaps — do not write

- **Design & generate other modalities (protein/peptide/biologics)** — spec 11.6 marks biologics **thin/not-built**. **Not-built → do not write** until shipped.
- **Billing / quota** — disabled. **Excluded** (task instruction).
- **IND Report flow** — page exists but hidden; **excluded** (do not restore per memory). Report/export tutorial (gap #2) must use the generic path, not IND.
- **CRO Library / drug-discovery-CRO** — disabled. **Excluded.**
- **Runs dashboard** — folded into Workflows; not a separate surface. Covered by S1/T3.

---

## 4. Summary for the second wave

**Write now (P1, known-working):**
- `T7-projects-and-collaboration.md`
- `T8-reports-edit-and-export.md` (generic report path, not IND — verify ask-to-edit + export first)
- `T9-connecting-data-and-tools.md` (data sources / databases / MCP / skills — verify skill add-flow UI first)

**Confirm scope against in-progress W1/M1/M2, then extend-or-split (P2):**
- Full step view & provenance (spec 08) — standalone unless W1 absorbs it
- Dataset versioning / lineage / access-scope (spec 04) — extend T4
- Composer in depth (spec 06) — extend T0

**Verify-before-writing (untested):** skill/expert add-flow UI, Models Train/Adapt/Optimise authoring, per-domain inference viewers.

**Do not write (not-built / disabled):** biologics modalities, billing, IND, CRO, separate Runs dashboard.
