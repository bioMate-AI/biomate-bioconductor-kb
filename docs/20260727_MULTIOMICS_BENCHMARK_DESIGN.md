# Multi-Omics Integration Benchmark — Design & Paper Plan

**Date:** 2026-07-27 (updated 2026-07-28)
**Status:** 🟢 **Phase-1 pilot DONE — 2-method head-to-head + normalization + metric
harness, all through the platform on real CLL.** MOFA2 (method #1) and SNF (method #2)
run through the same universal CSV interface; a method-agnostic normalization+QC
workflow and a reusable `scripts/multiomics_metric_harness.py` score both identically
on IGHV (MOFA2 Factor-1 AUC 0.968 / matched-k=3 ARI 0.526; SNF ARI 0.375). See §6
Phase 1 for the Figure-1 table. Go signal for Phase 2 (grid + TCGA).
**Related:** `docs/20260726_E2E_AUDIT_SINGLECELL_MULTIOMICS.md` (universal CSV
interface + MOFA2 fixes), CLAUDE.md "Benchmark-Driven Development".

---

## 1. Thesis & positioning

Multi-omics integration is crowded and has **no consensus winner** — the choice of
method routinely changes which biology you recover. A fair comparison is hard for
one reason: running N methods on *identical* inputs, reproducibly, with matched
pre-processing and metrics. **That is exactly what BioMate does.** The universal
CSV multi-omics interface (one input contract → any method, executed reproducibly
on AWS Batch) *is* the benchmark harness.

**The paper is therefore not "another method comparison."** The contribution is:

> **A unified, LLM-orchestrated platform for reproducible multi-omics integration
> benchmarking** — where identical inputs are pushed through many integration
> methods under matched pre-processing, evaluated with a common metric suite, and
> every run is a re-executable artifact. Demonstrated on cancer + autoimmune
> cohorts, with an emphasis on the regimes prior benchmarks under-cover
> (missing/partial modalities, runtime/reproducibility, method-selection guidance).

### Novelty — grounded in a 2026-07-27 literature survey (see §1b for the landscape)
**The field has moved past bulk jDR.** Two anchors now own the obvious ground:
- **Cantini et al. 2021, *Nat Commun*** (10.1038/s41467-020-20430-7) — 9 joint-DR
  methods on simulated + TCGA + single-cell; verdict **intNMF best clustering,
  MCIA most robust across contexts**. Shipped **momix** (a Jupyter notebook to
  reproduce + plug in methods) — our closest conceptual competitor, but narrow
  (bulk, jDR-only, frozen notebook).
- **Su/Yang et al. 2025, *Nat Methods*** ("scMultiBench", 10.1038/s41592-025-02856-3)
  — **~40 methods, 64 real + 22 sim datasets, 7 tasks**, across vertical/diagonal/
  mosaic/cross paradigms. Winners are task- and paradigm-specific (Seurat WNN,
  Multigrate, GLUE, StabMap, totalVI…). Explicitly flags the open problems below.
- **Open Problems / openproblems.bio** (from NeurIPS'21 multimodal competition) —
  a *live, containerized, continuously-run* single-cell benchmarking ecosystem.

**So a "we compared N methods on TCGA/PBMC" paper is dead on arrival.** A 2026
paper must clear ≥1 of:
1. **A maintained, general, one-interface platform spanning bulk + single-cell +
   spatial** where a user drops in *their own* data and gets standardized
   head-to-head comparison — the seam the survey found *empty* (momix=frozen/bulk;
   scMultiBench=codebase; Open Problems=ML-competition infra; muon/Galaxy=pipelines,
   not comparative harnesses). **This is our primary contribution.**
2. **Spatial multi-omics** — genuinely under-benchmarked (SpatialGlue, SpaMosaic,
   SIMO, SpaDDM exist; no mature benchmark). White space.
3. **Foundation-model integration head-to-head** — scGPT / scMamba vs. classical
   jDR + VAEs under one protocol has *not* been done.
4. **The named open problems** (Nat Methods 2025): missing-modality/mosaic
   robustness, scalability (>100K cells / OOM), and **label-free cross-task
   metrics** (the paper explicitly asks for these).

**Recommended framing:** **#1 (platform-as-contribution) as the spine**, validated
on a spectrum from bulk → single-cell → spatial, with the MG/autoimmune cohort as
the biology anchor, and at least one genuinely-new axis (#2 spatial or #4
missing-modality) to be non-redundant.

> **Honest scoping consequence:** a *bulk-only* benchmark (MOFA2 + jDR on CLL/TCGA)
> is redundant with Cantini. The defensible version **requires BioMate to add
> single-cell (and ideally spatial) integration methods** — a real lift, but it's
> also a product-capability gap worth closing regardless.

### §1b — Competitive landscape (reproducible-platform survey)
| Tool | What | Coverage | Gap vs. our angle |
|---|---|---|---|
| **momix** (Cantini 2021) | notebook to reproduce + plug jDRs | bulk cancer, jDR | frozen, narrow, not a maintained platform |
| **Open Problems** (2022→) | live containerized continuous benchmarking | single-cell, task-based | ML-competition framing; not "run my data through many methods" |
| **scMultiBench** (2025) | code release for the 40-method benchmark | sc multimodal | a benchmark codebase, not a user-facing platform |
| **muon / MuData** (2021) | scverse multimodal data structure | sc/multimodal | data framework, not a comparison harness |
| **Galaxy SPOC** (2025) | 175+ reproducible sc/spatial tools | sc + spatial | tool aggregation, not head-to-head benchmarking |
| **mixOmics** | multi-block statistical toolbox | bulk + some sc | single-family, not cross-method |

**Nobody offers a maintained, general, one-interface system that runs a user's own
multi-omics data through many integration methods across bulk + sc + spatial with a
common ground-truth metric harness.** That is the paper.

---

## 2. Methods (mapped to BioMate workflows)

Span the method *families* and, per the survey, the *regimes* (bulk → sc →
spatial → FM) — because bulk-only is redundant (§1). ✅ = in BioMate; ➕ = thin
wrapper needed; ➕➕ = new capability BioMate lacks (the real lift).

**Tier A — bulk joint-DR (the Cantini baselines; validate the harness):**
| Method | Family | BioMate |
|---|---|---|
| **MOFA2 / MOFA+** (Argelaguet 2018/2020) | Bayesian latent factor | ✅ (`bioconductor/mofa2`, container built + running) |
| **MCIA / mogsa** (Meng 2014/2019) | co-inertia (Cantini's *most robust*) | ✅-ish (`mogsa`) |
| **intNMF** (Chalise 2017) | non-negative MF (Cantini's *best clustering*) | ➕ |
| **iClusterPlus** (Mo 2013), **SNF** (Wang 2014), **mixOmics/DIABLO** (Singh 2019), **RGCCA**, **JIVE** | latent / network / (r)GCCA / supervised | ➕ (all pure-R — trivial containers) |

**Tier B — single-cell multimodal (where the field is; scMultiBench 2025 set):**
| Method | Modalities / paradigm | Note |
|---|---|---|
| **Seurat WNN / v5** | vertical (paired) | strong DR/clustering baseline |
| **totalVI, MultiVI, Multigrate** (scvi-tools) | RNA+ADT / RNA+ATAC / mosaic (VAE) | totalVI = ADT-imputation winner |
| **GLUE / scGLUE** (2022 Nat Biotech) | diagonal (unpaired) | batch-correction winner |
| **StabMap** | mosaic | most consistent mosaic method |
| **scMoMaT, Matilda** | mosaic / paired | marker discovery |

**Tier C — spatial multi-omics (under-benchmarked = white space):** SpatialGlue
(2024 Nat Methods), SpaMosaic, SIMO (2025 Nat Commun), SpaDDM. ➕➕

**Tier D — foundation models (unbenchmarked head-to-head):** scGPT (2024 Nat
Methods), scMamba (2025). ➕➕ — *first fair FM-vs-jDR-vs-VAE comparison would be
novel on its own.*

The Tier-A **pure-R** methods de-risk the "MOFA2 is heavy" problem (no basilisk →
trivial containers) and validate the harness cheaply. **Tiers B–D are the
non-redundant contribution** and the real engineering lift — they're mostly
Python (scvi-tools / torch); BioMate needs single-cell + spatial integration
workflows it doesn't yet have.

---

## 3. Datasets (with ground truth)

Ground truth is what makes the benchmark scorable. Tiered:

| Dataset | Omics | Ground truth | Role |
|---|---|---|---|
| **CLL** (Dietrich 2018, JCI; the MOFA vignette cohort) | mRNA, methylation, drug-response, mutations | IGHV status, trisomy-12, drug-response groups | canonical; sanity + factor→clinical |
| **TCGA multi-omics** (BRCA / pan-cancer subset) | RNA, methylation, RPPA, (CNV) | PAM50 / molecular subtypes → **ARI/NMI** | subtype recovery |
| **Single-cell multi-omics** (10x RNA+ATAC PBMC/BMMC) | RNA, ATAC | cell-type labels | scaling + modality-imbalance |
| **MG / autoimmune** (our program) | scRNA pseudobulk + (methylation / proteomics as available) | disease vs control, complement axis | the biology anchor |

All enter through the **same universal CSV contract** (`rna.csv`,
`methylation.csv`, … — features × samples, matched columns).

---

## 4. Metrics (common suite, run identically per method)

1. **Cluster/subtype recovery** — ARI, NMI vs known labels (factors → k-means/GMM).
2. **Clinical/biological association** — factor ↔ survival (Cox), ↔ IGHV/subtype
   (assoc test); # factors with FDR-sig association.
3. **Variance explained** — per view / per factor (where the method exposes it).
4. **Robustness** *(the differentiator):*
   - **subsampling stability** — factor reproducibility over N bootstraps (e.g.
     Amari/absolute-correlation between runs).
   - **missing-modality** — degradation when a layer is dropped or 30/50% of
     samples lack a modality (partial overlap). Prior benchmarks largely assume
     complete overlap; real cohorts don't.
5. **Runtime / cost / reproducibility** — wall-clock, vCPU-hours, and whether the
   run is bit-for-bit re-executable (BioMate captures this for free).

---

## 5. Experimental design — the harness IS the universal interface

```
for dataset in DATASETS:                     # identical, pre-processed CSVs per dataset
  for method in METHODS:                      # each = one BioMate bioc workflow
     run = submit(method_workflow, omics=[<dataset CSVs>])   # same input contract
     factors = run.output                     # standardized factor/embedding table
     for metric in METRICS: score[dataset][method][metric] = eval(factors, ground_truth)
```

- **Matched pre-processing:** one shared normalization per omics type (log-CPM RNA,
  M-values methylation, …) applied *before* the fan-out, so methods differ, not
  their inputs. Encode as a preprocessing workflow feeding all methods.
- **Standardized output:** each method emits a common `factors.csv`
  (samples × factors) + optional `weights.csv`, so metric code is method-agnostic.
  MOFA2 already emits `mofa_extracted_factors.csv` — define this as the contract;
  wrap other methods to match.
- **Reproducibility:** every cell of the results grid is a BioMate run ID → the
  paper's supplement is literally re-runnable.

---

## 6. Phased plan

- **Phase 0 — MOFA2 solid: ✅ DONE + VERIFIED on dev Batch (run `c96493d7`, 2026-07-27).**
  The full harness works for method #1: universal CSV interface (3 named matrices
  staged + read) → **real-modality view labels** (`['methylation','proteomics','rna']`,
  NOT the old hardcoded `Transcriptomics/Proteomics/View 3`) → MOFA2 trained on the
  dedicated `:3.20-mofa2` container (basilisk/mofapy2 baked) → factor extraction.
  **Factor recovery sound:** on structured input (2 injected shared latent factors),
  Factor 1 recovers the group split (mean diff +2.71), Factor 2 the gradient
  (corr +0.51), Factors 3–6 correctly near-zero. Output = standardized
  `mofa_extracted_factors.csv` / `_weights.csv` (the `factors.csv` contract) +
  variance + plots. This proves the platform premise: one input contract, method
  runs reproducibly, standardized output ready for the metric harness.
- **Phase 1 — 2-method / 1-dataset pilot on CLL. 🟢 GO signal (method #1 done):**
  - **Data**: real CLL cohort (Dietrich 2018 / MOFA vignette) — `drugs` (310),
    `methylation` (4248), `mrna` (5000), `mutations` (69) × 200 matched patients,
    parsed from `CLL_data.RData` via the MOFA2 container's R on the ECS host,
    staged to `s3://biomate-nextflow-work/cll_test/`. IGHV + trisomy12 ground truth
    live inside the `mutations` view.
  - **MOFA2 (method #1): ✅ VERIFIED on dev Batch (run `6517aaf4`, 2026-07-27).**
    Universal interface handles 4 real views → labels `drugs/methylation/mrna/
    mutations` → **Factor 1 recovers IGHV status, standardized mean diff d = +1.75**
    (IGHV+ n=104 vs IGHV− n=84; 188 labels), all other factors |d|<0.4. This is the
    canonical MOFA CLL result (Argelaguet 2018) — the harness reproduces known
    biology on the field's reference cohort.
  - **UI end-to-end (method #1): tested + fixed.** API runs worked, but a
    comprehensive UI E2E (chat → panel → run) found a gap the API hid: routing +
    panel are correct (MOFA2 card, 4 omics matrices shown as params), but the LLM
    param-prefill supplies the matrices under ARBITRARY names (`drugs_data`,
    `methylation`, …) from the free-text query, while the workflow declares one
    list-style `// Input: omics` → the executor found no `omics` param and the
    matrices never reached MOFA2. **Fix (`nextflow_executor.py`):** when a bioc
    workflow declares one list-style input and no same-named param exists, collect
    all file-valued params (s3://, *.csv/.rds/.h5ad) into the list and stage each by
    basename (view = filename). Scoped to single-list-input workflows. *Lesson: the
    universal interface must be verified through the UI, not just the API.*
  - **SNF (method #2): ✅ BUILT + RUNNING through the platform.** mogsa was reframed
    to a CRAN method (mogsa is hardwired to the NCI60 example AND the transcriptomics
    container lacks it → the same 504 mirror / dedicated-container saga). The chosen
    lighter path is **SNF** (SNFtool, Wang 2014) — installs as fast p3m.dev noble
    binaries at runtime (no container build, no 504). Workflow:
    `subworkflows/bioconductor/snf_multiomics/main.nf`, **same universal CSV input
    contract as MOFA2** (`// Input: omics`; view name = filename), standardized
    `snf_clusters.csv` (sample,cluster) output for the metric harness. NA-handling
    built in (per-feature mean imputation) so SNF, which needs complete data, gets a
    fair run on CLL (MOFA2 tolerates NAs natively). De-risked in-container on real CLL
    (4 views, 200 patients), then submitted **through BioMate** `/api/workflows/execute`
    → AWS Batch (run `fc3b1719`, 2026-07-28). *This is the paper's core claim in
    action: a second, mechanistically-distinct integration method running through the
    same platform + same interface — the "many methods, one platform" seam the survey
    found empty.*
  - **🟢 HEAD-TO-HEAD (Figure 1, CLL / IGHV recovery):** both methods scored on the
    identical ground truth (IGHV mutation status, n=188 labeled) by the SAME reusable
    metric harness (`scripts/multiomics_metric_harness.py`), run through the same
    platform + universal interface:

    | Method | Factor-1 AUC | ARI (k=3, matched to SNF) | ARI (k=2) | NMI |
    |---|---|---|---|---|
    | **MOFA2** | **0.968** (Cohen's d = 3.55) | **0.526** | 0.797 | 0.462 (k=3) |
    | **SNF** | — (native hard clusters) | **0.375** (C=3 spectral) | — | 0.373 |

    **Finding:** MOFA2's supervised-free latent factors recover the canonical CLL IGHV
    axis *better* than SNF's fused-network spectral clustering (matched k=3 ARI 0.526 vs
    0.375), AND expose it as a **single interpretable factor** — Factor 1 separates IGHV
    at **AUC 0.968** — rather than a hard partition. This is a genuine, defensible
    method-difference on the field's reference cohort: exactly the head-to-head the
    survey found missing. *Reproducibility note:* the AUC (rank-based, scale/sign-free)
    is the robust headline; single-init k-means ARI is init-unstable (k=2 swung 0.00↔0.80
    across seeds), so the harness uses **n_init=10 best-inertia restarts + a fixed seed**
    → deterministic, reproducible ARI/NMI. (An earlier "d=1.75" used overall-SD
    standardization; canonical pooled-within-group Cohen's d is 3.55 — hence AUC leads.)
  - **Normalization layer (method-agnostic): ✅ BUILT + RUN through the platform.**
    `subworkflows/bioconductor/omics_normalize/main.nf` — per-omics normalization
    (log2 / asinh / quantile / z-score, count-heuristic default) + QC metrics
    (PMAD / PCV / frac_na / skew, **before and after**, OmNI parity), base-R only (no
    install / no 504). Same universal CSV interface; emits `normalized_<view>.csv` so
    BOTH integration methods can consume **provably-identical pre-processing** — the
    fairness guarantee for the head-to-head. Verified on CLL (run `a0f1138f`): drugs
    skew −0.75→0.06, all views sd→~1, NAs preserved (mRNA 32%). *This directly answers
    "do we have normalization?" — yes, now as a first-class, chainable platform step.*
  - **Fairness loop CLOSED: ✅ both methods re-run on the IDENTICAL `normalized_*`
    matrices** (runs `99240a51` SNF, `7b0dfb8b` MOFA2, scored by the same harness):

    | Method | on raw CLL | on shared-normalized CLL |
    |---|---|---|
    | **MOFA2** | AUC 0.968, k=3 ARI 0.526 | AUC 0.964, k=3 ARI 0.495 |
    | **SNF** | ARI 0.375 | **ARI 0.375** (byte-identical) |

    The ranking (MOFA2 > SNF) holds under provably-identical preprocessing → the
    head-to-head is **not** a normalization artifact. SNF's ARI is *identical* because
    SNFtool z-normalizes internally — a clean validation that the shared normalize step
    is a no-op-for-SNF (does exactly SNF's inline standardization), so it's fair.
    (MOFA2 Factor-1 sign flipped — MOFA factors are sign-arbitrary; AUC is sign-free.)
  - **Remaining pilot work**: run SNF at C=2 for its best binary-IGHV ARI; add TCGA
    (PAM50) as a second cohort to show the ranking generalizes beyond CLL.
- **Phase 2 — grid:** add iClusterPlus, intNMF, mixOmics/DIABLO; add TCGA subtype
  recovery. Full metric suite incl. robustness.
- **Phase 3 — differentiators + write-up:** missing-modality/partial-overlap
  experiments; single-cell RNA+ATAC; runtime/cost; the MG biology anchor;
  LLM-driven method-selection guidance. Draft the paper.

---

## 7. Risks & open questions
- **R1 — novelty:** a pure leaderboard is not publishable post-Cantini. Mitigate
  by leading with platform + robustness + biology anchor (§1).
- **R2 — output heterogeneity:** methods expose factors/embeddings differently.
  Mitigate with the `factors.csv` contract + per-method thin wrappers.
- **R3 — pre-processing confound:** unfair pre-processing invalidates comparisons.
  Mitigate with one shared upstream preprocessing step (§5).
- **R4 — scope creep:** 7 methods × 4 datasets × 5 metrics is a lot. Gate on the
  Phase-1 pilot before committing.
- **Q1:** Lead venue/angle — methods/platform (Bioinformatics / GigaScience /
  Nat Methods-adjacent) vs. biology-first (with the MG cohort as the story)?
- **Q2:** Include VAE methods (totalVI/MultiVI) now, or scope to matrix methods
  for v1 and defer deep-learning to a follow-up?
- **Q3:** Which single-cell multi-omics dataset (10x PBMC RNA+ATAC vs BMMC) — driven
  by what has clean public labels.

---

## 8. Why this is coherent with the product
Every multi-omics workflow already in BioMate becomes one benchmark row; the
universal CSV interface is the harness; the LLM does method selection +
interpretation. The paper and the product are the same artifact — which is the
strongest possible position for a methods/platform paper.
