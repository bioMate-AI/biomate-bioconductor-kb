# Multi-Omics Foundation Roadmap — SOTA coverage E2E, THEN innovation

**Date:** 2026-07-28
**Governing principle (from the user):** *"Make sure each and every omics is working
with SOTA and the most efficient speed, data normalization, etc. in BioMate in an E2E
way — THEN propose innovations."* Foundation first. Innovation stands on it, not before.

**Why this ordering is correct (proven this session):** the "adaptive-weighted SNF"
innovation I floated already exists as **ANF** (Affinity Network Fusion, 2017 — an
explicit weighted SNF upgrade). Every "innovation" proposed without the full SOTA set in
front of us has turned out to be already-done. You only see the *real* gap once all the
outstanding methods run side-by-side. So: build the foundation, let the gap reveal itself.

---

## A. The SOTA method inventory to cover (from the two benchmarks that own this space)

### Bulk multi-omics integration (Cantini 2021, momix — 9 jDR methods)
Have: **MOFA2** ✓, **SNF** ✓ (both *middling* in Cantini — not the ones to lead with).
Add, in priority order (all pure-R / CRAN / Bioc, container-light):
| Method | Family | Why | Cantini verdict |
|---|---|---|---|
| **intNMF** | integrative NMF | **best clustering in Cantini** | 🥇 clustering |
| **MCIA** | co-inertia (omicade4/mogsa) | **most robust across contexts** | 🥇 robustness |
| **iClusterPlus** | Bayesian latent | canonical subtyping baseline | — |
| **RGCCA** | regularized generalized CCA | CCA family representative | — |
| **JIVE** | joint+individual variation | variance-decomp, MOFA sibling | — |
| **ANF** | weighted network fusion | the weighted-SNF SOTA (kills my "innovation") | — |
| (tICA, scikit-fusion, MSFA, iCluster) | complete the momix-9 | full parity | — |

### Single-cell multimodal (scMultiBench 2025 — ~40 methods; the winners)
Add the per-task leaders (these are the real SOTA, and the field's center of gravity):
| Task | Winners to cover |
|---|---|
| **Mosaic** (multi data-type) | **StabMap** (strong + most efficient), MultiVI, Cobolt, scMoMaT, Multigrate, UINMF |
| **Vertical** (same cells) | **Seurat v5 (WNN)**, MOJITOO, scAI, totalVI, UINMF |
| **Cross / imputation** | **totalVI**, StabMap, sciPENN, UnitedNet |
| **Diagonal** (unpaired) | **GLUE** |
> StabMap and totalVI recur across tasks — the highest-value first single-cell adds.
> These are Python (scverse/torch) — a different container track than the bulk R set.

## B. SOTA per-omics normalization (replace the current basic z-score)
The `omics_normalize` workflow currently does log2/asinh/quantile/z — generic. SOTA is
modality-specific:
| Omic | SOTA normalization |
|---|---|
| bulk RNA-seq (counts) | TMM/DESeq2 size factors → log-CPM / VST |
| microarray / continuous expr | quantile / RMA |
| DNA methylation (beta) | M-value transform, BMIQ/funnorm |
| scRNA | log1p(CP10k) or SCTransform / analytic Pearson residuals |
| scATAC | TF-IDF + LSI |
| proteomics / RPPA | VSN / median-centering |
| miRNA | log-CPM |
Each integration run must record which normalization was applied (provenance + fairness).

## C. Efficiency (the "most efficient speed" requirement)
- Per method, record runtime + peak memory on a standard cohort; publish a cost table.
- Bar to hit: StabMap is noted as the *most efficient* SOTA — anything we add should be
  profiled against a sane baseline, not just "it ran."
- Batch right-sizing per method (some are O(n²) in samples — SNF/ANF; others scale).

## D. E2E verification (per method × per omics, the real bar)
For each method added, verify THROUGH BioMate (chat → route → run → correct output):
1. Universal CSV interface accepts it; sample-intersect + normalization applied.
2. Runs on ≥1 canonical cohort (Rappoport TCGA for bulk; a scMultiBench set for sc).
3. Standardized output (clusters.csv / factors.csv) scores through the metric harness.
4. Recovers the known subtype at a level consistent with the source benchmark.
5. Runtime/memory recorded.
Only when a method passes all 5 is it "covered."

## E. Datasets/cohorts to stage (from the benchmarks)
- **Bulk:** Rappoport & Shamir 2018 — all 10 TCGA cancers (AML/BIC/COAD/GBM/KIRC/LIHC/
  LUSC/SKCM/OV/SARC), 3 omics + subtype/survival labels. (AML+BRCA already staged.)
- **Single-cell:** scMultiBench datasets (CITE-seq, 10x multiome, SHARE-seq…) — a
  representative subset per paradigm (vertical/mosaic/cross/diagonal).

---

## Build sequence (foundation, then innovation)
1. **Bulk SOTA set** (cheapest, infra exists): intNMF → MCIA → iClusterPlus → RGCCA →
   JIVE → ANF. Each: workflow + E2E on Rappoport cohorts + metric-harness scored.
2. **SOTA normalization** upgrade (modality-specific) feeding all methods.
3. **Efficiency profiling** table across the method set.
4. **Single-cell track** (new Python/scverse container): StabMap, totalVI, GLUE, Seurat WNN.
5. **Full benchmark reproduction** on canonical cohorts → establishes we match the field.
6. **ONLY THEN — innovation.** With every SOTA method running + normalized + profiled, the
   real gap (a modality/task/scale/robustness regime no method handles) becomes visible.
   That gap — not a guessed-at hybrid — is the innovation + high-end-publication candidate.

**Status:** starting step 1 with **intNMF** (Cantini's clustering winner) — the first
outstanding method, mirroring the SNF workflow's CRAN-light pattern.

Related: [[project_multiomics_benchmark]]; supersedes the premature "finding/paper" framing
in `docs/20260728_MULTIOMICS_FINDING_AND_COMPETITIVE_REASSESSMENT.md` (that work is now
demoted to an internal validation artifact, not a publication).
