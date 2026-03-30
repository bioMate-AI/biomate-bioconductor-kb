# BioMate AI — Pilot Study Plans (Directions C & D)

*Structural biology & single-cell genomics tracks · March 2026 · Confidential*

This document expands the partner-facing brief (`pilot_study_preparation_partner_brief.md`) and internal research survey (`BioMate_Research_Direction_Survey_20260303.md`) into executable pilot protocols for two directions: **Cryo-EM + AI structures** (UT Southwestern Cryo-EM Facility) and **single-cell perturbation / cell therapy profiling** (Baylor College of Medicine — Center for Cell and Gene Therapy).

---

# Direction C — Cryo-EM + AI Structures Pilot Study Plan

**Partner:** UT Southwestern Cryo-EM Facility

## 1. Scientific Objective

**Primary goal:** Run BioMate’s **CryoSPARC standard single-particle analysis (SPA)** pipeline on a partner-selected project and **benchmark end-to-end automation (plus QC governance) against the facility’s established manual CryoSPARC workflow** on the same inputs.

**Structure to be determined:** A **single consensus 3D reconstruction (sharpened map)** for one well-defined molecular target agreed at kickoff — e.g. a **membrane protein, viral capsid, or soluble complex** that the facility is already processing for publication. The pilot is *not* intended to discover a novel fold; it is intended to show that **automated, auditable processing reproduces the facility’s accepted reconstruction path** within agreed numerical tolerances.

**Resolution target:** Agreed **a priori** from the partner’s prior experience and dataset class (e.g. **sub-4 Å** for a high-signal purified specimen, or a **relaxed target** for challenging membrane or small protein targets). Internally, BioMate’s QC harness treats **FSC at the 0.143 cutoff** as the standard resolution reporting convention aligned with **EMDB map validation practice** and the widely used **FSC 0.143 criterion** discussed in the cryo-EM methods literature (e.g. Rosenthal & Henderson, 2003; community EMDB validation expectations for reported resolution).

**Why this matters for the partner:** The facility gains (i) a **time-stamped, citation-backed QC audit trail** suitable for methods text and collaborative review, (ii) **reproducible Nextflow/CryoSPARC execution** with explicit gates on motion, CTF, picking, classification, and refinement, and (iii) a **direct comparison** of curator hours and wall-clock time versus interactive processing — supporting core-facility throughput planning and multi-user standardization.

## 2. BioMate Capabilities Engaged

### Pipelines

- **23-step SPA pipeline** (survey specification): import movies → motion correction → CTF estimation → denoising → blob picking → junk detection → 2D classification (×2) → ab initio reconstruction → homogeneous refinement → CTF refinement → non-uniform refinement → local resolution → sharpening.
- **5-step cryo-ET pipeline** (optional stretch if partner supplies tilt-series data): import tilt series → tilt alignment → tomogram reconstruction → subtomogram averaging → full pipeline orchestration.

**Execution context:** BioMate supports **mock**, **live CryoSPARC v5 API**, and **open-source** execution modes; **8 GPU deployment profiles** and **4-level Nextflow parallelism** (movies → micrographs → particles → volumes) as described in the internal survey.

### Automated tests (43)

The cryo-EM domain regression suite referenced in the research survey comprises **43 passing tests** covering **tier-1/tier-2 QC gates**, **Volta phase-plate (VPP) CTF variants**, and **near-threshold warning** behaviour. Concretely, these exercises are anchored in `backend/tests/test_qc_e2e_domains.py` (and related harnesses), including representative classes such as:

| Cluster | What it validates |
|--------|-------------------|
| `TestFrankCryoEM` | End-to-end cryo-EM QC event routing and domain detection (`cryo_em` / `cryosparc_spa`) |
| `TestFrankRefinementFSC` | **FSC-based resolution gate** on homogeneous / non-uniform refinement and validation outputs |
| `TestCryoEM2DClassificationQCGates` | 2D classification QC thresholds and junk-class handling |
| `TestCryoEMSharpenLocalResolution` | Sharpening & local-resolution QC parsing |
| `TestVoltaPhasePlateCTFGates` | Phase-plate CTF QC paths |
| `TestCryoEM_ModelQuality` | Model-quality / map QA hooks |

*Operational note:* The pilot treats “43 tests” as the **release gate** for cryo SPA/ET QC logic before partner data touches the live executor.

### QC gates (evidence-graded)

BioMate applies **GOLD / SILVER / BRONZE** semantics per `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md` and the user guide `docs/user/03_read_qc_output.md`. For cryo-EM SPA, the pilot explicitly monitors:

| Step / metric | Role in pilot | Evidence anchor |
|---------------|----------------|-------------------|
| **Global resolution (FSC 0.143)** | Primary **map quality** comparator vs. partner’s manual job | **EMDB validation norms**; FSC 0.143 convention (Rosenthal & Henderson, 2003; EMDB processing expectations) |
| **CTF `fit_quality`** | Hard reliability gate on CTF estimation | **[SILVER]** CryoSPARC v4 score scale; values &lt; 0.7 indicate unreliable CTF (evidence table) — *user-facing docs may label this GOLD in places; the evidence register uses [SILVER]* |
| **Particle yield** | `particles_picked` minimum and **duplicate_fraction** | **[BRONZE]** ≥ 1,000 picked (practical floor); EMPIAR community guidance often cites **≥ 10,000** for high-resolution campaigns; **duplicate_fraction &gt; 20%** fails **[SILVER]** |
| **Motion / drift** | `total_drift_angstrom` | **[SILVER]** &gt; 50 Å fails (Grant & Grigorieff, 2015; CryoSPARC documentation) — proxies specimen thickness/charging/beam motion issues |
| **2D junk fraction** | `junk_2d_fraction` | **[SILVER]** &lt; 70% (CryoSPARC SPA defaults, per user QC table) |

**Ice thickness:** Not all thickness metrics are exposed as first-class automated gates in every CryoSPARC export path. For EMDB readiness, the pilot treats **ice thickness and estimated defocus distribution** as **partner-validated metadata** checked against **EMDB primary map deposition checklist** items (half-maps, FSC curves, pixel size, symmetry, masking description, etc.) and captured in the **exportable QC report**.

### AutoFix behaviour (cryo-EM–relevant failures)

AutoFix (`galaxy.ai.workflow_ops.autofix`, including AutoFix 3 orchestration) is designed to **classify failures**, **adjust parameters where safe**, and **restart** workflows. For cryo-EM pilots, the following failure modes are expected to dominate:

| Failure mode | Typical cause | AutoFix-style response (conceptual) |
|--------------|---------------|-------------------------------------|
| **CTF fitting failure / low `fit_quality`** | Wrong defocus search range, thick ice, bad patch size, phase-plate miscalibration | Patch-size / search-window suggestions via **CryoEMParameterSuggester** routing; escalate to human if below hard gate |
| **Low particle yield after picking** | Blob picker thresholds mis-matched to particle size/contrast | Threshold / box-size retries; switch picking strategy only if workflow variant exists |
| **GPU OOM / memory errors** | Box size too large, too many parallel micrographs | Batch-size reduction, parallelism downgrade, or GPU profile change (e.g. AWS vs. local_gpu) |
| **Motion correction correlation collapse** | Drift/charging; bad gain reference | Re-run with adjusted motion parameters; flag SILVER drift gate |

*Pilot requirement:* Every AutoFix attempt is logged to the **audit trail** (parameters before/after, invocation id).

### AlphaFold3 model comparison

Per the internal survey, **AlphaFold3 integration for map fitting is a documented HIGH-priority gap**, not a committed pilot gate. **If** a short integration sprint completes before the pilot ends, an **optional add-on milestone** compares a **predicted coordinates model** to the **refined map** (e.g. reporting cross-correlation / visual fit in QC). **Default pilot scope:** map + FSC + CTF/particle/motion QC only.

## 3. Study Protocol (4–6 week timeline)

| Week | Activity | BioMate Role | Partner Role | Expected Output |
|------|----------|--------------|------------|-----------------|
| **1** | Kickoff & data contract | Provision project workspace; confirm GPU mode (live CryoSPARC vs. mock vs. open-source fallback) | Nominate **target molecule**, appoint **1 cryo-EM operator**, share **data layout** (movies vs. pre-processed) | Platform registration complete + dataset manifest |
| **2** | Ingest & dry run | Run **mock or subset** pipeline; validate **QC parsers** on partner file formats (MRC/TIFF/EER) | Upload **representative subset**; confirm **pixel size, gain, dose, tilt** metadata | QC trace on subset; format fixes if needed |
| **3** | Full SPA automated run | Execute **23-step SPA** with chosen **named profile** (`cryoem_spa_purified`, `cryoem_spa_membrane`, or `cryoem_spa_phase_plate`) | Provide **gold-standard manual job** parameters (for fair comparison) | Sharpened map + JSONL QC audit |
| **4** | Benchmarking | Compute **Δ resolution (FSC 0.143)**, **CTF**, **particle statistics**, **wall-clock** vs. manual | Timed **manual** processing log (hours of hands-on work) | Comparison table |
| **5** | EMDB readiness review | Generate **QC report draft** (HTML/PDF per product roadmap) | Map checklist against **EMDB deposition requirements** | Go / no-go for supplementary deposition package |
| **6** (optional) | ET stretch OR AlphaFold3 add-on | Run **5-step ET** *or* integrated AF3 comparison if available | Provide tilt series *or* atomic model priority | Stretch milestone report |

## 4. Evaluation Metrics

| Metric | Hypothesis it tests | Measurement method | Target value | Failure threshold |
|--------|---------------------|--------------------|--------------|-------------------|
| **Map resolution (FSC 0.143)** | Automated SPA matches expert processing | Parse CryoSPARC / job output FSC 0.143 Å | Within **±10%** of partner manual map *or* within **0.3 Å** (whichever is looser), pre-agreed | **&gt;20%** worse resolution *and* expert declares map unusable |
| **CTF `fit_quality`** | CTF estimation is stable | Logged QC value vs. threshold | ≥ **0.7** (profile-adjusted if VPP) | **&lt;0.5** sustained after AutoFix → **engineering escalation** |
| **Particle yield** | Picking is efficient | Accepted particles ÷ picked (or vs. manual pick count) | ≥ **70%** of manual yield *or* ≥ **10k** particles for high-res target | **&lt;1,000** picked (BRONZE gate) → stop & redesign picking |
| **Processing time** | Automation saves curator time | Instrumented timestamps + partner time diary | **≥2× faster** wall-clock *or* **≥50%** reduction in **hands-on hours** | No time benefit *and* worse QC → pilot fails |
| **EMDB submission readiness** | QC artefact matches deposition norms | Partner + BioMate checklist review | **100%** of *available* automated metrics documented with citations | Missing **mandatory** metadata fields with no workaround → **needs engineering / process fix** |
| **Researcher satisfaction** | Trust & usability | 5-point Likert exit survey (see partner brief hypotheses) | **≥4/5** on “trust QC” | **≤2/5** triggers UX review |
| **Hallucination rate (tool steps)** | AI proposes only valid tools/parameters | Telemetry: invalid tool name / schema errors / impossible parameters | **0** critical hallucinations per run | Any **silent wrong tool** → **severity-1 bug** |

## 5. Data Requirements

- **Inputs (any of):** Raw **movies** (preferred for full 23-step path) in **MRC, TIFF, or EER**; or **motion-corrected micrographs** if the pilot scope is narrowed; or a **public EMPIAR / EMDB** replicate dataset if partner data is unavailable.
- **Instrument metadata:** **Accelerating voltage (kV)**, **detector (e.g. K3 / Falcon 4i)**, **pixel size (Å)**, **total electron dose (e⁻/Å²)**, **defocus range**, **gain reference**, **tilt geometry** (if ET).
- **Minimum dataset size:** **≥500–1,000 micrographs** for a serious SPA benchmark; **≥10,000 auto-picked particles** for high-resolution claims per community guidance (EMPIAR notes in QC evidence). Smaller sets allowed for **QC harness validation only**, not resolution claims.

## 6. Success Criteria

**Success (publishable pilot outcome):**

- Sharpened map within **pre-agreed resolution tolerance** vs. manual processing.
- **SILVER-or-better** outcomes on **CTF**, **motion**, and **2D junk** metrics, or documented overrides with scientific justification.
- **≥70%** of exit-survey respondents rate QC narrative as **publication-ready or near-ready** (aligns with partner brief Assumption 2).
- Complete **audit JSONL** + methods-ready parameter summary.

**“Needs engineering fix” trigger:**

- Systematic **GPU / license / filesystem** failures blocking execution.
- **AutoFix loops** &gt; **N** attempts (e.g. 3) without convergence on CTF or picking.
- **FSC parser / QC gate** disagreement with ground-truth CryoSPARC UI on **two independent datasets** (indicates monitoring bug).

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Live CryoSPARC license / GPU unavailable | Medium | High | Start on **EMPIAR** data with agreed cloud GPU; use **mock_mode** for UI/QC validation |
| Partner data format edge case | Medium | Medium | Week **2** subset dry-run; explicit **format contract** |
| QC threshold mismatch for exotic specimen | Medium | Medium | Select **`cryoem_spa_membrane`** or **`cryoem_spa_phase_plate`** profile up front |
| AlphaFold3 not ready | High | Low | Keep **out of critical path**; document as roadmap item |
| IRB delays | Medium | High | Use **public EMPIAR** replicate; narrow PHI/PII surface |

---

# Direction D — Single-Cell Perturbation Pilot Study Plan

**Partner:** Baylor College of Medicine — Center for Cell and Gene Therapy

## 1. Scientific Objective

**Primary goal:** Use **single-cell RNA-seq** to **profile immune and engineered cell therapy products** (e.g. **CAR-T, CAR-NK, or gene-edited lymphoid populations**) and quantify how quickly BioMate produces a **QC-governed, annotated UMAP atlas** with **differential abundance** summaries compared with the lab’s **manual Seurat / Scanpy** workflow.

**Cell types profiled (illustrative — finalized at kickoff):** **CD3+ T cells, NK cells, myeloid cells, B cells**, and **transduced/engineered subsets** defined by **transgene or reporter** where available.

**Biological questions (select ≥1):**

- **Exhaustion / dysfunction:** enrichment of **PD-1, CTLA4, LAG3, TIM3** programs post-expansion.
- **Off-target activation / stress:** unexpected **IFN-γ, IL-6, TNF** programs or **heat-shock / unfolded protein** signatures in product cells.
- **Composition drift:** batch-to-batch **clonal diversity** and **subtype proportions** vs. release criteria.

## 2. BioMate Capabilities Engaged

### Tooling & QC profiles

- **79 single-cell tools** cataloged (per research survey) with **14+ Bioconductor** wrappers (e.g. annotation / abundance tooling such as **clustifyr**, **speckle**, **singlecelltk**, **m3drop**, etc. — exact tool list is versioned in the unified tool index).
- **Three named QC profiles** for scRNA-seq: **`scrna_standard`**, **`scrna_cardiac`**, **`scrna_neuronal`** (extended mitochondrial tolerance for high-mito tissues).
- **`scrna_perturbation`** profile (documented in `docs/user/03_read_qc_output.md`) for **Perturb-seq / CROP-seq** style screens — **guide coverage + doublet-oriented gates** once the engineering sprint lands.

### Analytical features in scope

- **Seurat / Scanpy-class workflow:** filtering, normalization, **clustering**, **UMAP**, **marker-based cell-type annotation**, and **differential abundance** between conditions or manufacturing batches.
- **QC gates relevant to pilot:**
  - **Mitochondrial fraction:** science target **≤20%** per **Luecken & Theis, 2019** single-cell best-practices framing; BioMate implements **>20%** as a **BRONZE advisory** with **10–20% near-threshold warnings** (see `docs/QC/20260224_QC_THRESHOLDS_EVIDENCE.md` — cardiac/neuronal profiles relax explicitly).
  - **Genes / cells:** **`median_genes_per_cell` ≥500** advisory (10x Cell Ranger v7–aligned user table); minimum genes-per-cell and cells-per-gene cuts as workflow defaults.
  - **Doublet detection:** identified in the survey as a **medium-priority implementation gap**; Month 1 uses **profile + heuristic filters** if doublet tools are unavailable, and Month 2 targets **Perturb-seq doublet gates** post-sprint.

### Staged roadmap

| Stage | Scope | Readiness |
|-------|-------|-----------|
| **Month 1** | **scRNA-seq** immune profiling → clustering → annotation → differential abundance | **Ready now** (per partner brief) |
| **Month 2** | **CRISPR / Perturb-seq** readouts | Requires **2-week engineering sprint** before onboarding |

### 2-week CRISPR screen engineering sprint (pre–Month 2)

The sprint **unblocks perturbation-native analysis** by delivering:

1. **Pertpy integration** (Python perturbation toolkit) for **standardized perturbation matrices** and statistical tests where applicable.
2. **Guide RNA assignment** pipeline: map **UMI + guide barcode** features to **sgRNA identity** using lab-supplied **library reference**.
3. **Perturbation effect testing:** **global hit** summaries (e.g. MAGeCK-class or edgeR-style screens where wired) + **single-cell layer** contrasts (target gene programs vs. non-targeting controls).

*Note:* Internal survey originally estimated **3–4 weeks** for a full Perturb-seq stack; the **2-week sprint** is a **minimum viable path** to **guided pilot data** — scope must be **frozen** at sprint planning.

## 3. Study Protocol (staged: Month 1 + Month 2)

### Month 1 — scRNA-seq immune profiling (weeks 1–4)

| Week | Activity | BioMate Role | Partner Role | Expected Output |
|------|----------|--------------|------------|-----------------|
| **1** | Intake | Configure **`scrna_standard`** (or cardiac if justified) | Share **10x** sample sheet, batch IDs, **cell hashing** flags if any | Platform registration + sample manifest |
| **2** | Ingest | Connect **Cell Ranger–compatible** inputs; run QC parsers | Upload **matrix or FASTQ** | QC JSONL + cell/gene stats |
| **3** | Atlas | Clustering, UMAP, **annotation** | Provide **marker gene panel** / prior labels | Annotated UMAP |
| **4** | Diff. abundance + survey | Batch vs. batch contrasts | Review biology | Report + satisfaction survey |

### Month 2 — Perturbation track (conditional on sprint completion)

| Week | Activity | BioMate Role | Partner Role | Expected Output |
|------|----------|--------------|------------|-----------------|
| **5** | Sprint hardening | Deploy **Pertpy + guide mapping** MVP | Freeze **library CSV** | Regression tests on public Perturb-seq example |
| **6** | Pilot perturb run | End-to-end **guide assignment → QC → hits** | Upload **CRISPR screen 10x** dataset | Hit table + QC audit |
| **7–8** (optional) | Integration with Month 1 | Joint **therapy + screen** narrative | Biological validation | Combined figure deck |

*If sprint slips:* Month 2 converts to **additional scRNA-seq batches** only — no perturbation claims.

## 4. Evaluation Metrics

| Metric | Hypothesis it tests | Measurement method | Target value | Failure threshold |
|--------|---------------------|--------------------|--------------|-------------------|
| **Cell-type annotation accuracy** | Automated labels match expert biology | Confusion matrix vs. **marker-gene reference panel** (≥5 canonical markers per major type) | **≥85%** concordance at **major-lineage** level | **&lt;70%** → annotation workflow redesign |
| **Clustering resolution** | Data structure is not over-smoothed | **Silhouette** (or graph-based modularity if silhouette ill-defined) | Silhouette **≥0.25** *or* expert accepts visual separation | Persistent **&lt;0.15** with obvious batch swamp |
| **Doublet detection rate** | Data cleanliness | **Expected doublet rate** vs. tool calls (when enabled) | Within **2×** of 10x expected doublets | **&gt;15%** removed without expert sign-off |
| **Differential abundance power** | Batch effects controlled | **Pseudobulk** or **MiloR / speckle-class** tests (tool-dependent) | **≥1** statistically robust contrast (FDR **&lt;0.05**) matching expert prior | Zero significant hits where biology expects strong signal |
| **Time FASTQ → annotated UMAP** | Automation reduces turnaround | Timestamp telemetry vs. partner **manual baseline** | **≤60 minutes hands-off** compute *or* **≥50%** faster than manual calendar time (per brief) | Slower than manual **without** QC benefit |
| **Researcher satisfaction** | Usable for IND / publication drafts | 5-point Likert | **≥4/5** overall | **≤2/5** triggers UX + tool audit |

## 5. Data Requirements

- **10x Genomics Chromium:** **filtered feature-barcode matrix (H5 / MTX)** — *preferred*; **Cell Ranger BAM** if re-processing needed; **FASTQ** if starting from raw base calls.
- **Minimum cells:** **≥5,000–10,000** cells for stable clustering on heterogeneous immune products; **≥500 cells per biological condition** for basic abundance contrasts (higher if rare subsets matter).
- **Metadata:** donor ID (de-identified), **batch**, **timepoint**, **vector copy number** if available, **stimulation** conditions.
- **CRISPR screen (Month 2):** **guide library reference** (CSV/TSV: `sgRNA_id`, sequence, optional target gene); **10x CRISPR feature reference** JSON if using 10x-curated panels.

## 6. Success Criteria

**Month 1 success:**

- QC narrative passes partner review (**mito, genes/cell, counts**) with **≤1 manual parameter override** per **5 workflows** (partner brief Assumption 1).
- **Annotated UMAP** delivered with **exportable QC report**.
- **Differential abundance** result matches expert directionally on **≥1** validated contrast.

**Month 2 success (if enabled):**

- **≥90%** reads with **assignable guides** among singlets.
- **Hit list** overlaps **≥50%** of manual MAGeCK/edgeR hits (top decile) on positive controls.

**Engineering escalation:**

- Persistent **doublet / guide mapping** failures after sprint.
- **Tool not found** or **schema hallucination** events &gt;0 in production logs.

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| **2-week sprint underestimates Perturb-seq complexity** | Medium | High | **Time-box** MVP; defer **trajectory** tools (Monocle3, scVelo) per survey gap list |
| **Batch effects dominate biology** | High | Medium | **Harmony / scVI** embeddings if available; block **Month 2** until Month 1 batch models work |
| **Clinical sample sensitivity** | Medium | High | **De-identified** metadata only; institutional IRB alignment |
| **Low cell recovery post-manufacturing** | Medium | Medium | Lower **cells-per-gene** thresholds via documented overrides; focus on **relative abundances** |
| **Tooling gaps (doublets, spatial)** | Medium | Medium | Transparent **QC advisories**; manual doublet removal documented side-by-side |

---

*Document owner: BioMate Product & Science Liaison · For partner review — do not distribute externally without sign-off.*
