# Multi-Omics Integration Benchmark — Design & Paper Plan

**Date:** 2026-07-27
**Status:** Design proposal. Phase-1 pilot runnable on BioMate once ≥2 methods work
through the universal interface (MOFA2 = method #1, container just built).
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

- **Phase 0 — MOFA2 solid (DONE/near):** universal CSV interface + label
  preservation deployed; dedicated MOFA2 container built & pushed
  (`:3.20-mofa2`). Verification run pending deploy. This is method #1 + proof the
  harness runs.
- **Phase 1 — 2-method / 1-dataset pilot:** MOFA2 + one pure-R method (MCIA or
  SNF) on **CLL**. Wire the standardized `factors.csv` output + a metric script
  (ARI vs IGHV, factor↔drug-response). Goal: prove the harness end-to-end and
  sanity-check that scores reproduce known CLL biology. **This is the go/no-go.**
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
