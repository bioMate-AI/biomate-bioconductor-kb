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

### Novelty vs. the landmark benchmark
The reference is **Cantini et al. 2021, *Nat Commun*** ("Benchmarking joint
multi-omics dimensionality reduction approaches for the study of cancer") — MOFA,
JIVE, MCIA, RGCCA, intNMF, scikit methods on TCGA + single-cell. Also **Tini et
al. 2019, *Brief Bioinform*** and **Subramanian et al. 2020** (review). A rerun
adds nothing. Our defensible deltas:
1. **Platform / reproducibility as the contribution** (not just a leaderboard) —
   one interface, containerized methods, re-runnable artifacts, LLM-driven method
   selection + interpretation. This *is* the product.
2. **Under-covered regimes:** partial-overlap / missing-modality robustness;
   single-cell & spatial multi-omics; runtime/cost at scale.
3. **Biology anchor:** the MG/autoimmune program (see §4) — which integration best
   recovers known immune / drug-response structure, a question a generic cancer
   benchmark doesn't answer.

**Recommended framing: #1 + #3** (platform-as-contribution, demonstrated on a
biology question we own).

---

## 2. Methods (mapped to BioMate workflows)

Pick a spread across method *families* (not 8 variants of one idea). ✅ = already
in BioMate; ➕ = needs a thin workflow wrapper.

| Method | Family | Supervision | Heavy deps? | BioMate |
|---|---|---|---|---|
| **MOFA2 / MOFA+** (Argelaguet 2018/2020) | Bayesian latent factor | unsupervised | ⚠ basilisk/Python | ✅ (`bioconductor/mofa2`, container built) |
| **mixOmics / DIABLO** (Rohart 2017; Singh 2019) | sparse (r)GCCA | supervised | pure R | ➕ (mixOmics in bioc) |
| **MCIA / mogsa** (Meng 2014/2019) | co-inertia | unsupervised | pure R | ✅-ish (`mogsa`) |
| **iClusterPlus** (Mo 2013) | joint latent + clustering | unsupervised | pure R | ➕ |
| **intNMF** (Chalise 2017) | non-negative MF | unsupervised | pure R | ➕ |
| **SNF** (Wang 2014) | similarity network fusion | unsupervised | pure R | ➕ |
| *(stretch)* **totalVI / MultiVI** (Gayoso 2021) | VAE | unsupervised | Python | ➕ |

The **pure-R** methods matter twice: they broaden family coverage AND de-risk the
"MOFA2 is heavy/fragile" problem (no basilisk conda env → trivial containers).

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
