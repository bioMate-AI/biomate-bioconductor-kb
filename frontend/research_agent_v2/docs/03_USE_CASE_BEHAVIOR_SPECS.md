# Use-case Behavior Specs — what real BioMate must do per workflow type

**Date:** 2026-05-18
**Source split:**
- **Visual** (look, layout, colors, fonts, animations, copy tone) →
  follow `reference/claude_design/research_agents/` literally. The
  design is prettier and friendlier than what we have today.
- **Content** (phase names, step counts, gate metrics, default params,
  citations) → use BioMate's **actual** workflow definitions in
  `backend/biomni_workflows/nextflow_nfcore/subworkflows/`, the AI
  tool DB at `backend/database/galaxy_ai_tools.db`, and BioMate
  domain knowledge. **Do not** copy the example phase names / step
  counts from the design's `research-data.js` or Tour.jsx tape — those
  are illustrative and not necessarily accurate.

The five use cases the user flagged for careful review and what BioMate
workflow each maps to (verified against the live tool DB):

| # | Use case | BioMate workflow | DB id | Real step count | Domain |
|---|---|---|---|---|---|
| 1 | Cryo-EM | CryoSPARC Standard Single-Particle Analysis | **12833** | 23 | cryo_em |
| 2 | After-run report | (workflow-agnostic — every completed run) | — | — | all |
| 3 | Drug screen | Predict ADMET Properties (AI) + auto-loop | **12826** | 1 (+ auto-loop) | drug_discovery |
| 4 | Bulk RNA-seq | nf-core/rnaseq | **1491** | 8 | transcriptomics |
| 5 | Variants | nf-core/sarek | **1493** | 6 | variant_calling |

Per use case, this doc lists:

- **Scenario** — the user query
- **Workflow content (from BioMate)** — the actual phases / steps /
  gates / params / citations to surface
- **Visual treatment (from design)** — the look + behaviors
- **Already in BioMate** — what we ship today
- **Missing in BioMate** — what we still need to build
- **Acceptance criteria**

---

## 1. Cryo-EM single-particle analysis

### Scenario
"Run single-particle reconstruction on EMPIAR-10025 (or similar dataset)."
Raw movies → sharpened 3D map.

### Workflow content (from BioMate — `cryosparc_standard_spa/main.nf`)

The real workflow has **23 processes**. They group naturally into 5
phases based on the science (motion + CTF → picking → 2D class →
3D reconstruction → sharpening), but the .nf file does **not** today
carry `// [Phase X]` annotations like the drug-discovery workflows do.
We need to add those annotations so the panel can group them — phase
boundaries inferred from the process names we already have:

| Phase | Phase name | Real processes in `main.nf` |
|---|---|---|
| **A** | Motion correction + CTF | `INIT_CRYOSPARC_PROJECT`, `SPLIT_INTO_BATCHES`, `PATCH_MOTION_CORRECTION_BATCH`, `PATCH_CTF_ESTIMATION_BATCH`, `MERGE_MICROGRAPHS`, `MICROGRAPH_DENOISER` |
| **B** | Particle picking + extraction | `BLOB_PICKER_BATCH`, `INSPECT_PICKS`, `TEMPLATE_PICKER`, `SPLIT_PARTICLE_BATCHES` |
| **C** | 2D classification | (process names containing CLASS_2D / select_classes — verify in main.nf) |
| **D** | 3D reconstruction | `AB_INITIO_BATCH`, `HOMO_REFINEMENT_BATCH`, `MERGE_VOLUMES`, `NON_UNIFORM_REFINEMENT`, `LOCAL_CTF_REFINEMENT` |
| **E** | Sharpening + validation | `VOLUME_TOOLS`, `VALIDATION_FSC`, `LOCAL_RESOLUTION`, `MERGE_CLASSES` |

**QC gates that exist in BioMate today** (per `qc_trace_monitor.py`
review — verify each before shipping):
- CTF fit quality (CTFFIND4 confidence)
- 2D class quality (`select_2d_classes` cutoff)
- B-factor sharpening (must be from manifest, not inferred)
- GSFSC threshold (0.143 for resolution reporting)

**Citations to surface in the After-run report** (from our tool DB
tools_used field for workflow 12833):
- MotionCor2 (PMID-driven citation; tool DB has the PMID)
- CTFFIND4
- Topaz (if used for picking) or blob picker
- CryoSPARC version + container image SHA

### Visual treatment (from design)

- **Sticky plan checklist** above chat: 5 phase chips with status
  pills. **Only active phase auto-expands**; others collapse to chip.
- **Chat speaker pills**: `WF` blue for workflow events, `QC` amber
  for the CTF gate warning, `LOOP` purple if auto-loop applies a fix.
  Pill colors **stable** across plan / chat / panel.
- **CTF halt card** when the gate trips: inline chat card with
  metric / observed / threshold / proposed fix (defocus range
  widening). Actions: `Accept` / `Edit values` / `Dismiss` +
  **per-phase auto-loop toggle**.
- **Step outputs land inline** on the step row in the workflow panel
  the moment Nextflow's trace marks COMPLETED. For cryo-EM:
  `.mrc` micrographs, particle stack files, half-maps, final map.
- **After-run report at panel bottom** auto-appears on completion
  with 7 tabs (Findings / Outputs / Methods / Parameters / Software /
  Citations / QC audit).
- **Findings tab** for cryo-EM specifically:
  - Headline metric: final resolution in Å (from manifest)
  - GSFSC value at 0.143
  - B-factor (from manifest)
  - Particle count after final select
  - Map deposition-ready flag
- **Footer button** changes `Confirm and run workflow` →
  `Run again` on completion.

### Already in BioMate (production)

- Workflow itself (id 12833) ✓
- Per-step output preview/download inline on step rows ✓
- QC monitor reading `workflow-trace.txt` ✓ (commit `23ad63a3d`)
- `workflow.phase_started`, `workflow.qc_gate_warning`,
  `workflow.qc_gate_blocked` narrator events ✓ (commit `7668498b4`)
- DeepAnalysisAgent for diagnosing failures ✓
- Methods report download endpoint ✓

### Missing in BioMate

- **`// [Phase A-E]` annotations** in
  `cryosparc_standard_spa/main.nf` (currently has none). Without these,
  the panel can't group 23 processes into 5 phase chips.
- **Sticky plan checklist component** (Surface 1 from design spec).
- **Speaker-pill rendering** on the existing 🔹 italic chat lines
  (Surface 2).
- **CTF halt card** as a dedicated inline chat card (today the QC
  gate fires a chat line but doesn't render a halt-card with a
  suggested fix + accept/edit actions).
- **Per-phase auto-loop toggle in PhaseCard** with the citation
  footer.
- **After-run 7-tab panel** as a single embedded component (today
  the same info is scattered across multiple endpoints).
- **Findings generator** that reads resolution / GSFSC / B-factor
  from the cryo-EM run manifest (no inference).
- **Citations aggregator** that pulls tool PMIDs from
  `workflows.tools_used` for the run's tools.

### Acceptance criteria

- [ ] `cryosparc_standard_spa/main.nf` carries `// [Phase A-E]`
      annotations on the right processes (review with cryo-EM SME)
- [ ] User asks for cryo-EM SPA → sticky plan shows 5 phase chips
- [ ] Each phase ticks live as Nextflow trace updates
- [ ] CTF gate trip surfaces a halt card with measured CTF
      resolution + threshold + suggested defocus widening
- [ ] Step `.mrc` outputs and final map appear inline on the
      respective step rows
- [ ] After-run section shows 7 tabs; Findings tab has resolution +
      GSFSC + B-factor read straight from the manifest
- [ ] Methods tab IMRaD prose includes MotionCor2 + CTFFIND4 + the
      picker + CryoSPARC version
- [ ] QC audit tab shows the CTF gate event with chain-of-custody

---

## 2. After-run report (workflow-agnostic)

### Scenario
Every completed run, regardless of workflow type, gets a 7-tab After-run
section at the bottom of the workflow panel. The user can download a
single bundled report.

### Workflow content (from BioMate)

The After-run report is **driven by the run manifest**, which BioMate
already generates. Per tab:

1. **Findings** — headline metric per workflow type, pulled from the
   manifest. Workflow-type-specific generators (e.g. cryo-EM reads
   final resolution; RNA-seq reads DE gene count; ADMET reads
   candidate count after QC).
2. **Outputs** — file list from `s3_output_files` (already populated
   by `_list_s3_output_files`).
3. **Methods** — IMRaD prose. We have a generator
   (`/api/invocations/{id}/methods-report`). Extend to flag inferred
   values vs. manifest-read with italics.
4. **Parameters** — every param the run touched. Source: the
   `_runs` entry + Nextflow's effective `params.json`. Tag defaults
   vs. user-overrides vs. auto-loop adjustments separately.
5. **Software** — container image SHA + each tool's version.
   Source: workflow's `tools_used` field + the container manifest
   we emit during run. **Reproducibility baseline.**
6. **Citations** — pre-formatted reference list. Source: each tool
   in `tools_used` has a `pmid` field in our tool DB; join them.
   PMIDs link to PubMed.
7. **QC audit** — every gate event during the run. Source: the
   `ai_fix_audit_log` table (Alembic migration `a7f3deepagent` from
   commit `4ec1d56b8`). Chain-of-custody. **E-signature block
   conditional** on the workflow having a `requires_signature`
   tag (CRO compliance only).

**Download report** — a single endpoint produces DOCX / Markdown /
LaTeX bundling all 7 tabs. We already have a DOCX path for the IND
report (`drug-discovery-ind-assembly.tsx`); generalize it.

### Visual treatment (from design)

- Section docks at the panel bottom when `runState === 'completed'`.
- Header: section title + `Download report` link with format
  dropdown (DOCX / Markdown / LaTeX).
- 7 tabs in **natural read order** — narrative first (Findings),
  raw artifacts next (Outputs), reproducibility (Methods /
  Parameters / Software), references (Citations), audit (QC audit).
- **Inline file preview** modal on `view` — table → sortable grid,
  plot → plotted image, 3D map → viewer, FASTA / VCF / text → code
  block.
- "**Author judgment**" badge on findings without a citation
  (subtle gray pill).
- **21 CFR Part 11 e-signature** block — dark backdrop modal when
  signing (trust signal); chain-of-custody timestamp + operator
  cert ID rendered in monospace.

### Already in BioMate

- `/api/invocations/{id}/methods-report` ✓
- `ChatOutputAttachments` component lists outputs ✓
- File-type preview modal already exists ✓
- QC audit table exists ✓ (commit `4ec1d56b8`)
- Tool DB has PMIDs per tool ✓
- E-signature path for IND track ✓

### Missing in BioMate

- **The single 7-tab After-run section component**, embedded in the
  workflow panel bottom. Today the same data is scattered.
- **DOCX / Markdown / LaTeX bundler** that wraps all 7 tabs.
  Generalize the IND DOCX path.
- **Citations aggregator** per run (currently no citations panel).
- **Findings generator per workflow type** (cryo-EM, RNA-seq, ADMET,
  Sarek). A registry of `workflow_domain → findings_fn`.
- **"Author judgment" badge** rule in the findings generator.
- **General-purpose e-signature gating** by `requires_signature` tag.

### Acceptance criteria

- [ ] Every completed run shows the After-run section at panel
      bottom (regardless of workflow type)
- [ ] All 7 tabs render with content from the run manifest
- [ ] `Download report` produces DOCX / Markdown / LaTeX bundles
- [ ] Findings tab: workflow-type-specific generator runs
- [ ] Outputs tab: every file in `s3_output_files`, with `view` +
      `download`
- [ ] Citations tab: PMIDs from tool DB, PubMed links
- [ ] QC audit tab: chain-of-custody for every gate event
- [ ] For workflows tagged `requires_signature`: e-sig block
      rendered + signing flow available

---

## 3. Drug screen (ADMET + auto-loop + comparison)

### Scenario
"Screen this 10,000-compound library for BBB penetrants" (or similar
hERG / DILI / Ames-gated screen).

### Workflow content (from BioMate)

The real workflow is `Predict ADMET Properties (AI)` (id 12826,
1 step) chained with the ADMET auto-loop subworkflow under
`experiments/admet_autoloop/`. The auto-loop fires gates on:
- **hERG**: predicted hERG inhibition probability > threshold (commonly
  > 0.5). Citation: Aronov 2008.
- **DILI**: drug-induced liver injury probability > threshold.
  Citation: Lammert 2010 (FDA DILI score).
- **Ames**: Ames test mutagenicity probability > threshold.
  Citation: Kazius 2005 (toxicophores).
- **Rule of Five (Ro5)**: Lipinski violations.

Auto-loop **remediation** strategies (from `experiments/admet_autoloop/`):
- Drop compounds above hERG threshold (filter step).
- Tighten `logp_max` / `mw_max` to prune off the chemical space
  showing systematic hERG hits.

**Sub-task decomposition** for a screen of N compounds:
1. **Ingest** — read input SMILES / SDF, validate.
2. **ADMET prediction** — batch through the ADMET workflow.
3. **hERG gate** — evaluate per compound, flag failures.
4. **Ames + DILI gates** — same.
5. **Ranking** — composite score over the passing compounds.

(These names are descriptive. They map to actual Nextflow processes
under the ADMET subworkflow; verify against `main.nf` before shipping.)

**Comparison content** when the auto-loop produces a re-pilot Run B:
- Metrics: hERG pass rate, Ames pass rate, DILI pass rate, candidate
  count, runtime, cost. p-value on the primary gate's pass rate.
- Parameter diffs **tagged by origin**:
  `logp_max: 5.5 → 4.5 [autoloop]`, `mw_max: 550 → 480 [autoloop]`.
- Recommendation: preferred run + confidence (high if
  primary-gate p < 0.01).

### Visual treatment (from design)

- **Plan checklist** with 5 sub-tasks. Pilot is implied because the
  screen is heavy (DeepAgent line: "Heavy — worth a pilot.").
- **`AGENT` chat line** in teal: pilot recommendation.
- **Pilot prompt card** inline in chat: sampling fraction (5% =
  500 compounds) + strategy + side-by-side full vs pilot cost.
- **QC failure mid-pilot**: plan items flip **amber warn pills in
  place**; QC chat lines fire with **amber speaker pills** —
  **colors match** the plan pills exactly.
- **Pilot promotion card** with auto-loop suggested fix shown
  inline. Action button: `Apply fixes and re-pilot`.
- **`LOOP` speaker pill** (purple) for every auto-loop decision
  line — clear audit trail.
- **Run-vs-Run comparison card** inline in chat. Metrics table with
  Δ column + parameter diffs (origin-tagged) + recommendation badge
  (preferred run + confidence + p-value).
- **10-second auto-pick** countdown on the recommendation button
  when confidence is high; hover pauses; click commits.
  Auto-fire emits "No response — using Run B automatically."
- **Findings chat card** at completion: candidate count + QC
  pass-rate + link to After-run report.
- **`(why?)` hover** on step lines exposes the rationale for the
  tool choice (e.g. why this ADMET model).

### Already in BioMate (production)

- ADMET workflow + auto-loop ✓
- hERG / DILI / Ames / Ro5 QC gates in `qc_trace_monitor.py` ✓
- Auto-loop param remediation ✓
- `workflow.qc_gate_warning` / `qc_gate_blocked` /
  `autoloop_started` narrator events ✓ (commit `7668498b4`)
- `is_pilot` + `dataScope.fraction/strategy` schema ✓
- `compareExecutionRuns` API ✓ (with the `parameterDifferences`
  gap — WC-7 test expects it but storage doesn't populate)
- DeepAnalysisAgent capable of producing rationale ✓

### Missing in BioMate

- **`PilotPromptCard`** rendered inline in chat
- **`PilotPromotionCard`** with auto-loop fix shown + Apply-and-re-pilot
- **`ComparisonCard`** inline in chat (today: no UI at all)
- **`parameterDifferences` populated** by `storage.compareExecutionRuns`
  (WC-7 gap)
- **Speaker pill rendering** on the existing QC / LOOP / AGENT
  chat lines (the events fire, the pill UI does not)
- **`(why?)` rationale anchor** on chat lines (new endpoint
  `/api/research/rationale/{phase_id}`)
- **High-confidence auto-pick** wiring on the comparison card
- **Findings chat card** at completion

### Acceptance criteria

- [ ] User asks for ADMET screening → plan with 5 sub-tasks +
      `AGENT` chat line recommends pilot
- [ ] Pilot prompt card shows in chat with 5% sample + cost preview
- [ ] Pilot runs; hERG / Ames trip; plan items flip to amber warn
      pills; QC chat lines fire with amber speaker pill (colors
      match plan)
- [ ] Pilot promotion card shows the auto-loop's proposed
      `logp_max` / `mw_max` adjustments inline
- [ ] User clicks `Apply fixes and re-pilot` → re-pilot under LOOP
      speaker; both gates pass
- [ ] Comparison card appears with metrics + param diffs (origin-
      tagged) + recommendation + p-value
- [ ] High-confidence (p < 0.01) → 10s auto-pick on recommended
      button
- [ ] Full run on Run B params completes; Findings chat card shows
      candidate count

---

## 4. Bulk RNA-seq (nf-core/rnaseq · id 1491 · 8 steps)

### Scenario
"Differential expression on 120 bulk RNA-seq samples."

### Workflow content (from BioMate — nf-core/rnaseq)

The DB says 8 steps. Real nf-core/rnaseq subworkflow phases (verify
against the actual subworkflow but these are the canonical groupings):

| Phase | Phase name | Real processes |
|---|---|---|
| **A** | Read QC | FASTQC, FASTQ_TRIM_FASTP |
| **B** | Alignment | STAR_ALIGN (with `alignIntronMax`, `outSAMtype` params) |
| **C** | Quantification | SALMON_QUANT (or RSEM, configurable) |
| **D** | Differential expression | DIFFERENTIALABUNDANCE → DESeq2 |
| **E** | Pathway / GO enrichment | clusterProfiler / enrichGO (parallel group with D) |

**QC gates** that exist or should exist:
- FastQC pass per sample (already in production)
- Mapping rate ≥ 70% (STAR alignment quality)
- Library complexity / duplication thresholds

**Citations**: STAR (Dobin 2013, PMID 23104886), Salmon (Patro 2017,
PMID 28263959), DESeq2 (Love 2014, PMID 25516281), etc. All available
in our tool DB.

**Decomposition** (per `TaskDecomposer`):
1. Read QC (FastQC on all samples — parallelizable)
2. Trim adapters (parallelizable across samples)
3. Align (STAR — parallelizable across samples)
4. Quantify (Salmon — parallelizable across samples)
5. Differential expression (DESeq2 — single step on all samples) ┐ parallel
6. Pathway enrichment (clusterProfiler — single step on DE results) ┘

### Visual treatment (from design)

- **Plan checklist with 5 sub-tasks + parallel-group glyph (⇄)**
  between the DE step and the pathway enrichment step.
- **`AGENT` chat line** recommending a pilot because 120 samples is
  heavy.
- **Pilot prompt card** with 10% (12 samples) + strategy.
- **Pilot promotion card** with all QC ✓ → default `Stop here`
  with 10s auto-proceed (Auto-Proceed convention: full runs need
  explicit opt-in).
- **User clicks `Run full pipeline`** → full run starts.
- **`WF` speaker pill** chat lines per phase event.
- **Per-phase auto-expand** in the workflow panel; non-active phases
  collapse to chip.
- **Findings chat card** at completion: sample count + DE gene
  count at adj-p < 0.05 + top enriched pathway + link to report.

### Already in BioMate

- nf-core/rnaseq workflow ✓ (id 1491)
- Phase wire-ins on real 3-process AWS Batch ✓ (commit `23ad63a3d`,
  verified)
- Pilot mode plumbing (`is_pilot`, `dataScope`) ✓
- DESeq2 / clusterProfiler workflows in DB ✓

### Missing in BioMate

- Same chat-side surfaces as drug screen above
- **Parallel-group rendering** in the PlanChecklist (the `Task`
  dataclass already has `parallel_with` per `TaskDecomposer:224`,
  but the UI doesn't render the ⇄ glyph)
- **Findings generator for RNA-seq**: read DE gene count +
  top-pathway from the manifest

### Acceptance criteria

- [ ] User asks "DE on 120 RNA-seq samples" → plan with 5 sub-tasks,
      DE + pathway joined by ⇄ glyph
- [ ] AGENT pilot recommendation chat line lands first
- [ ] Pilot card shows 12 samples + cost preview
- [ ] Pilot runs, all QC ✓, promotion defaults to `Stop here`
- [ ] User clicks `Run full pipeline` → full run starts
- [ ] Phase events tick the plan in real time
- [ ] Findings chat card at completion shows DE gene count + top
      pathway

---

## 5. Variants (nf-core/sarek · id 1493 · 6 steps)

### Scenario
"Call variants on this WGS sample with the patient cohort." Failure
recovery path: one chunk fails, retry just that chunk.

### Workflow content (from BioMate — nf-core/sarek)

The DB says 6 steps. Real sarek phases:

| Phase | Phase name | Real processes |
|---|---|---|
| **A** | Alignment | BWA-MEM (or DRAGMAP) — one task per sample, often parallelized |
| **B** | Duplicate marking | PICARD MARKDUPLICATES — per sample |
| **C** | Base quality recalibration | GATK BaseRecalibrator + ApplyBQSR — per sample |
| **D** | Variant calling | GATK HaplotypeCaller — **per chromosome × per sample** (nested parallelism — 23 chunks per sample for whole-genome) |
| **E** | Variant annotation | VEP / SnpEff |

**QC gates**:
- Coverage threshold (≥ 30× for WGS)
- Duplicate rate ceiling
- Mapping quality minimum

**Citations**: BWA (Li 2009, PMID 19451168), GATK HaplotypeCaller (Poplin
2018, bioRxiv), VEP (McLaren 2016, PMID 27268795).

### Visual treatment (from design)

- **Nested plan items** — the parent "Variant calling" item shows
  its sub-items indented (Per-chromosome HaplotypeCaller × 23 chunks).
- **Step failure mid-run**: one chunk fails (e.g. transient OOM).
  Plan item **flips to red + expands** to show failure reason +
  `Retry` / `Skip` / `Ask DeepAgent` buttons inline.
- **User clicks `Retry`** → just that chunk re-runs (Nextflow
  `-resume` semantics).
- **Run completes** despite the transient failure.
- **QC audit** logs the retry chain — auditable "step X retry 1,
  retry 2, …" entries.

### Already in BioMate

- nf-core/sarek workflow ✓ (id 1493)
- Per-step rerun via Nextflow `-resume` ✓
- `workflow.phase_failed` event fires on real Nextflow exit ≠ 0
  ✓ (commit `23ad63a3d` — verified with the MIDDLE_FAIL test)
- DeepAgent diagnosis on failed invocations ✓
  (`/api/workflows/{id}/deep_diagnose`)

### Missing in BioMate

- **Nested plan rendering** (parent + indented children with
  vertical connector line). The `Task` dataclass has `dependencies`
  (line 127 of `task_decomposer.py`); the renderer needs to show
  parent / child.
- **Inline failure block in the plan checklist** with `Retry /
  Skip / Ask DeepAgent` actions. Today failure surfaces in the
  workflow panel; we need it ALSO in the sticky plan.
- **Per-chunk retry granularity** in the UI — for 23
  per-chromosome chunks, the user shouldn't see 23 separate red
  items; collapse them under the parent, surface "21 of 23 succeeded,
  2 retried" in the plan.
- **QC audit chain-of-custody for retries** — verify the audit log
  records retries as individual rows, not just final outcome.

### Acceptance criteria

- [ ] User asks "call variants on this WGS sample" → plan with 5
      phases + Variant calling phase shows nested
      per-chromosome sub-items (collapsed by default)
- [ ] A chunk fails → plan flips red on that chunk + shows
      `Retry / Skip / Ask DeepAgent` inline
- [ ] User clicks Retry → just that chunk re-runs
- [ ] Run completes; After-run QC audit tab shows the retry's
      chain-of-custody (gate event → fail → retry → success)

---

## 6. Cross-cutting expectations

All five use cases share these visual + behavior expectations from the
design:

1. **Two-pane layout**: chat (left) + workflow panel (right), kept
   in sync via SSE.
2. **Sticky plan above chat** for any decomposed query (≥ 2 sub-tasks).
3. **Speaker pills** on every 🔹 chat line; colors stable across
   plan / chat / panel.
4. **Inline cards, not modals** for all decision points (pilot,
   promotion, comparison, halt).
5. **10s auto-proceed** with per-decision defaults (Auto-Proceed
   Conventions table in design spec).
6. **`(why?)` rationale anchor** on phase chat lines.
7. **Outputs land inline on the step row** the moment Nextflow's
   trace reports COMPLETED.
8. **After-run report at panel bottom** for every completed run.
9. **Audit trail by speaker** (`LOOP` lines = auto-loop, `AGENT` =
   DeepAgent, `QC` = gate evaluations).
10. **Calm, factual tone** — "Workflow finished. 5 of 5 steps
    succeeded." Not "🚀 Awesome!"

---

## 7. Build order

The user's use-case priority is also the implementation priority. Each
ships behind a feature flag.

| # | Use case | Why this order |
|---|---|---|
| 1 | **Bulk RNA-seq happy path** | Simplest scenario; exercises Plan + speaker pills + pilot + findings in one tutorial. No QC trip / no comparison / no nested plan. Validates all 4 chat-side surfaces. |
| 2 | **Drug screen with auto-loop + comparison** | Adds the Comparison card; validates QC trip + auto-loop end to end. Uses everything from #1 + new comparison surface. |
| 3 | **Variant calling with nested plan + retry** | Adds nested plan rendering + inline retry. Failure recovery focus. |
| 4 | **Cryo-EM full deep dive** | Exercises all above + the After-run heavy tabs (Findings / Methods / Citations) for cryo-EM specifically. Needs `[Phase A-E]` annotations in main.nf first. |
| 5 | **After-run report 7-tab consolidation** | Workflow-agnostic; depends on findings generators per type. |

Effort estimate stays at ~11.5 days linear / ~7 days parallelized.

---

## 8. Open questions specific to use-case content

(Different from the design-review open questions in the design spec.)

1. **Phase annotations for cryo-EM** — adding `// [Phase A-E]`
   comments to `cryosparc_standard_spa/main.nf` needs SME review.
   Should phases A and B be merged ("preprocessing")? Should
   sharpening + validation be one phase or two?
2. **nf-core/rnaseq sub-process mapping** — verify the 8 DB steps
   match our 5-phase grouping. (DB step_count is generation-time
   count; runtime processes can be more due to parallel sample
   handling.)
3. **Sarek nested chunks** — when do we render per-chromosome
   chunks? Always? Only when count > 5? Recommend: collapsed under
   the parent by default; expand on click; show "N of M succeeded"
   summary in the parent row.
4. **ADMET sub-task names** — verify against the actual auto-loop
   subworkflow `main.nf`. The 5-name list above (Ingest / ADMET
   prediction / hERG gate / Ames gate / Ranking) is descriptive
   and may not match the actual process names 1:1.
5. **Citation rendering** — how do we resolve PMID → reference
   format (Vancouver vs. APA)? Recommend: pre-formatted in tool DB,
   keep it simple.

---

## 9. What this doc is NOT

- **Not a port of Tour.jsx tutorials into production.** Those stay
  in the sandbox as reference scripts for the design behaviors.
  Production doesn't ship an in-app guided tour for these flows.
- **Not a re-do of the design spec.** The design spec defines
  surface behavior generically. This doc applies it per workflow
  and grounds the content in real BioMate workflow definitions.
- **Not a launch checklist.** Each surface has its own E2E test
  plan in the design spec; this doc lists acceptance criteria per
  use case.
