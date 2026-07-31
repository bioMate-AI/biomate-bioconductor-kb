# BioMate Multi-Omics Integration Platform — Master Record

**Living document — updated continuously.** Single source of truth for the multi-omics
integration + benchmarking work, structured for tech reports, manuscripts, and marketing.
Last updated: 2026-07-30.

> **Honesty contract (applies to every claim here):** every number traces to a real
> run ID + the reproducible scorer (`scripts/multiomics_metric_harness.py`). Competitive
> claims are checked against the literature. Refuted hypotheses are kept, marked REFUTED —
> they are part of the honest record. No adjective-stacking novelty.

---

## 1. What this is (honest positioning)
BioMate runs a user's own multi-omics data through **multiple SOTA integration methods**
via one plain-English → AWS-Batch pipeline, with a **shared universal CSV interface**,
**SOTA per-modality normalization**, and a **reproducible metric harness** — then compares
the methods head-to-head. Contribution type: a **tool/resource** (accessibility +
your-own-data + breadth + reproducibility), NOT a new method and NOT a novel benchmark
finding (Cantini 2021 already showed "no universal winner"). The genuine differentiator
under construction: unifying the SOTA of BOTH the bulk (Cantini) and single-cell
(scMultiBench) worlds under one living, your-own-data platform, plus the wet-lab DBTL loop
software-only competitors (OmniBioAI, OmicOS, OmicsNavigator, OMICX, CEPICS) can't copy.

## 2. Integration methods — inventory + status
| Method | Family | Status | CLL/IGHV (k2) | AML/cyto (k3) | BRCA/PAM50 (k4) |
|---|---|---|---|---|---|
| **MOFA2** | latent factor (ARD) | ✅ solid | **0.797** | 0.093 | 0.202 |
| **SNF** | similarity network fusion | ✅ solid | 0.705 | 0.174 | 0.323 |
| **intNMF** | integrative NMF | ✅ solid | 0.705 | 0.160 | 0.221 |
| **MCIA** | co-inertia | ✅ solid (fixed 07-30) | 0.778 | **0.237** | **0.332** |
| **MFA** (base-R SVD) | multi-block factor | ✅ solid (07-30) | **0.876** | 0.125 | 0.189 |
| **iClusterPlus** | Bayesian latent | ⚠️ TCGA weak (undertuned) | 0.778 | 0.033 | 0.167 |
| **JIVE** | joint+individual var | ⚠️ TCGA weak | 0.652 | 0.085 | 0.112 |
| **StabMap** (single-cell) | mosaic embedding | ❌ needs mosaic data | — | — | — |

**7 methods now run E2E.** Per-cohort leaders: **MFA** on CLL (0.876), **MCIA** on both
TCGA (0.237/0.332). Still no universal winner — leader changes by cohort.

All matched-k (k = label class count), fair, through the platform, scored by the harness.

**Headline results (defensible):**
- **No universal winner** (now over 6 methods): MOFA2 wins CLL; **MCIA wins both TCGA
  cohorts** (0.237 / 0.332) — validating Cantini's "MCIA most robust." Method choice is
  data-dependent → you must benchmark.
- **MCIA fix (07-30):** near-random on TCGA (0.058/0.006) → competitive (0.237/0.332).
  Root cause: nsc-COA has no per-feature scaling, so TCGA's high-magnitude expression block
  swamped methylation/miRNA. Fix: per-feature standardization before the COA.

**Open method work:** iClusterPlus TCGA tuning (more MCMC / features); JIVE TCGA; MFA needs
a Deriv-free CCA-family method (FactoMineR & RGCCA both pull the un-compilable `Deriv`);
StabMap needs a true mosaic single-cell dataset (CITE-seq is paired/vertical → wrong tool).

## 3. Omics coverage + SOTA normalization
**Universal CSV interface** (features × samples, one matrix per modality, sample-intersect
across views). **SOTA per-modality normalization** (`omics_normalize`, auto-detected):
| Modality | SOTA transform | Status |
|---|---|---|
| bulk RNA-seq / miRNA | log2-CPM | ✅ base-R |
| scRNA | log1p(CP10k) (scanpy std) | ✅ base-R |
| DNA methylation (β) | M-value (Du 2010) | ✅ base-R |
| scATAC | TF-IDF (Signac/ArchR) | ✅ base-R |
| proteomics / RPPA | log2 + median-centre | ✅ base-R |
| drug-response / continuous | quantile | ✅ base-R |
| mutation / CNV | pass-through | ✅ |
| (refinements) | VSN / TMM / SCTransform-residuals | ⏳ install-gated, deferred |

**Validated on real data (~6 types):** bulk expression, methylation, miRNA, drug-response,
mutations, CITE-seq RNA+ADT (staged). **NOT yet validated:** proteomics MS, metabolomics,
scATAC, spatial, CNV, RPPA, microbiome. Interface is universal *in principle*; SOTA norm
now covers the prominent types but needs runtime validation per modality.

## 4. Benchmark capability ("run N methods on one dataset, compare")
- **Decision:** implemented as a **backend orchestrator** (fan out to N individual method
  runs — which run flawlessly — then score in the backend), NOT a composed nextflow
  workflow (that path hit 4 execution bugs incl. a COMPARE head-kill). **User selects which
  methods to compare** (method-picker, not auto-all).
- **UI reuse (checked):** `step-output-preview.tsx` renders CSV reports as tables for free;
  the workflow panel handles run/monitor; only a small chat-routing branch + the method
  picker (`multiselect` param case) are new.
- **Status:** orchestrator design + draft in progress; composed-workflow attempt retained
  as `multiomics_benchmark/main.nf` (methods run; scoring step fragile).

## 5. Datasets (staged, real)
- **CLL** (Dietrich 2018): drugs/methylation/mRNA/mutations × 200; IGHV ground truth.
- **TCGA** (Rappoport & Shamir 2018 benchmark): AML (cyto-risk), BRCA (PAM50) staged;
  8 more cancers available. GBM (Verhaak) next.
- **CITE-seq** PBMC (10x 5k): RNA + ADT × 2000 cells (labels RNA-derived → de-risk only).

## 6. Competitive positioning (honest)
| Prior work | What | Our delta |
|---|---|---|
| Cantini 2021 (Nat Commun) | 9 bulk jDR methods, static notebook | your-own-data + maintained + cloud + LLM |
| scMultiBench 2025 (Nat Methods) | 40 sc methods, static codebase | unify bulk+sc under one interface |
| CEPICS 2019 | 5-method cancer-subtyping platform | broader methods + normalization + not cancer-only |
| OmniBioAI / OmicOS / OMICX | LLM omics agents | + fair method-benchmark + wet-lab loop |

**Science-advantage bet (Path B, honest 50/50):** missing-modality / mosaic robustness by
method mechanism — the named open problem. Seed result (2×2): equal-weight fusion (SNF)
fragile to a junk view; ARD/latent methods robust. Noise-robustness across 6 methods:
directionally holds (only SNF degrades) but SUBTLE for pure noise. Predictor "standalone
alignment → marginal value": **REFUTED** (r≈0). Real test = partial-overlap (staged, not run).

## 7. Key files
- Methods: `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/{mofa2,snf,intnmf,mcia,iclusterplus,jive,rgcca(=MFA),stabmap_singlecell}_multiomics/main.nf`
- Normalization: `.../omics_normalize/main.nf` · Benchmark: `.../multiomics_benchmark/main.nf`
- Metric harness: `scripts/multiomics_metric_harness.py`
- Companion docs: `20260727_MULTIOMICS_BENCHMARK_DESIGN.md`, `20260728_MULTIOMICS_FOUNDATION_ROADMAP.md`,
  `20260728_FINDING_AND_COMPETITIVE_REASSESSMENT.md`, `20260728_ADVANTAGE_AND_TWO_PATHS.md`,
  `20260728_SINGLECELL_TRACK_SCOPING.md`, `20260730_BENCHMARK_ORCHESTRATOR_DESIGN.md`

## 8. Change log (append each significant step)
- **2026-07-30 (latest):** MFA base-R SVD verified — **7th method working** (CLL 0.876 best /
  AML 0.125 / BRCA 0.189). Benchmark orchestrator endpoint LIVE (POST fans out user-selected
  methods → child runs); fixed getRun adapter (read execution.status, not top-level → children
  were stuck "unknown"). Single-cell + DL/FM integration registry created
  (`20260730_SINGLECELL_TOOLS_DATA_RESOURCES_TO_INTEGRATE.md`): P0 = MultiVI/totalVI (scvi GPU
  container) vs classical — serves DL-track + mosaic regime; FMs (scGPT/scMamba/UCE) to
  benchmark-not-assume (VCBench / "one PCA rules them all" show FMs lose to baselines).
- **2026-07-30 (later):** SOTA normalization VALIDATED on mixed TCGA-BRCA (run) — modality
  auto-detection correct on all 3 views: exp→rnaseq→log2-CPM (mean 2984→6.36), methy→
  methylation→M-value (β 0.45→−0.59), mirna→log2-CPM. MFA reimplemented in base-R
  (block-weighted SVD, zero install → Deriv failure class eliminated; de-risk pending).
  Orchestrator wiring into routes.ts in progress.
- **2026-07-30:** MCIA per-feature-scaling fix → TCGA 0.058/0.006 → 0.237/0.332 (now top on TCGA).
  SOTA per-modality normalization shipped (log2-CPM/log1p-CP10k/M-value/TF-IDF/median-centre).
  Benchmark → backend-orchestrator decision (composed workflow hit COMPARE head-kill).
  Master record created (this file). MFA blocked (Deriv); StabMap needs mosaic data.
- **2026-07-28/29:** 6-method × 3-cohort matched-k matrix; MFA/StabMap drafts; competitive
  reassessment (platform novelty largely gone); two-path plan (tool + science).
- **2026-07-27:** Phase-1 pilot (MOFA2 vs SNF on CLL); universal interface; metric harness.
