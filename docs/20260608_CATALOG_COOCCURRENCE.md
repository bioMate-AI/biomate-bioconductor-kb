# BioMate Catalog — Co-occurrence & Connectivity Analysis

**Date**: 2026-06-08
**Companions**:
- `docs/20260608_CATALOG_AUDIT.md` (counts)
- `docs/20260608_CATALOG_DEEP_DIVE.md` (BGE gap, general bucket, semantic fit)

This pass looks at how workflows and tools *combine* in the catalog: ordered pairs, hub workflows, domain transitions, and infrastructure-vs-method tools. Five findings that reshape some earlier numbers.

## 1. Workflow re-use in curated chains is highly concentrated

Of 74 ordered (A → B) step transitions across the 29 curated chains:

**Hub workflows** (re-used across many chains):

| Workflow | Chains | Role |
|---|---|---|
| `nf-core/rnaseq` | **8** | Backbone for almost every bulk RNA-seq chain |
| `predict_admet_properties` | 6 | Drug-discovery backbone |
| `nf-core/differentialabundance` | 3 | Standard DE step |
| `structure_prediction_docking` | 3 | Docking backbone |
| `pharmacophore_filtering` | 3 | Drug-screen prefilter |
| 13 other workflows | 2 each | secondary anchors (e.g. `BIOC_DESeq2`, `BIOC_limma`, `pbpk_simulation`) |

**Implication**: the curated catalog reuses a small set of hub workflows. Adding more curated chains will mostly compose existing hubs into new orderings. This is good for verifier grounding (LLM sees recurring real names) but means we're not exploring the long tail of 3,695 workflows.

## 2. Domain transitions are overwhelmingly same-domain

Of the 8 ordered pairs where BOTH endpoints are in the catalog with known domains:

| From | To | Count |
|---|---|---|
| transcriptomics | transcriptomics | 3 |
| drug_discovery | drug_discovery | 3 |
| transcriptomics | drug_discovery | 1 |
| drug_discovery | pharmacology | 1 |
| transcriptomics | epigenomics | 1 |

**Cross-domain pairs that are verifiable in our catalog: 3.** The earlier "17/29 curated chains span multiple sources" number was misleading — those spans typically involve placeholder step names (not in the catalog) rather than two real cross-domain catalog workflows.

The user's "connect different specialties via seamless cross-domain chains" vision is **barely represented even in the manually curated catalog today**. We have:
- 3 cross-domain transitions, all manually authored
- 1 verifiable cross-source pair (e.g. `nfcore` → `bioc`)
- 65 pairs (out of 74) where one or both names are placeholders we haven't grounded

This is the gap. The L2 (pattern + LLM compose) and L3 (free composition) paths are the only realistic way to surface cross-domain links at scale.

## 3. `tools_used` is mostly infrastructure, not capability

Per-domain top tools (from `workflows.tools_used` JSON):

| Domain | Top 5 tools |
|---|---|
| transcriptomics | bioconductor/ggplot2 (103), summarizedexperiment (58), knitr (53), singlecellexperiment (49), dplyr (45) |
| genomics | samtools/idxstats (22), bioconductor/ggplot2 (17), samtools_index (16), samtools/index (16), bioconductor/knitr (15) |
| drug_discovery | ambertools, antechamber, tleap, cpptraj, rdkit (all 2) |
| proteomics | bioconductor/ggplot2 (14), biocstyle (13), knitr (12), dplyr (11), spectra (9) |
| variant_calling | tabix (8), bioconductor/ggplot2 (8), gatk4/mutect2 (6), bcftools/index (6), knitr (5) |
| epigenomics | bioconductor/genomicranges (16), ggplot2 (13), knitr (12), summarizedexperiment (11), rtracklayer (9) |
| cryo_em | CryoSPARC (7), mrcfile (4), TOPAZ (2), MotionCor2 (1) |

**Pattern: `bioconductor/ggplot2`, `knitr`, `dplyr` dominate most domains** because the catalog indexes R/Bioc package dependencies — not the analytical method. Only the explicitly non-R domains (cryo_em, drug_discovery) show distinguishing tool patterns.

**Implication**: `tools_used` cannot be used as a "what does this workflow DO" signal — it's a "what runtime does it need" signal. Pattern retrieval that relies on `tools_used` over `description + annotation` will produce noise.

## 4. `step_count` is library-size, not pipeline-length

The audit reported "8% of workflows have 11+ steps." This is misleading. The 10 largest by step_count:

| Steps | Domain | Name | What it actually is |
|---|---|---|---|
| 222 | general | `sevenbridges` | API client library — 222 *functions*, not 222 chained steps |
| 122 | variant_calling | `GWASTools` | GWAS analysis suite (each function indexed as a step) |
| 100 | general | `MutationalPatterns` | Mutational signature analysis library |
| 91 | transcriptomics | `systemPipeR` | Pipeline composer — many wrapper functions |
| 88 | epigenomics | `extraChIPs` | ChIP-seq utility collection |
| 87 | transcriptomics | `cummeRbund` | Cufflinks output visualization library |
| 75 | single_cell | `SpatialFeatureExperiment` | Single-cell + spatial data structure |
| 61 | general | `biocGraph` | Graph data structures for Bioc |
| 61 | transcriptomics | `recount` | Public RNA-seq compendium |
| 58 | genomics | `SeqArray` | SNP array data container |

**These are not "long pipelines" — they're large libraries where each function got indexed as a step.** This means:
- `step_count > 10` is a poor proxy for "complex pipeline"
- The shape of indexable units in the catalog is heterogeneous: some entries are single-function tools, others are 100-function packages
- A workflow with 30 steps isn't necessarily 30 sequential operations; it might be 30 alternative entry points into the same package

For chain composition: we should treat high-step-count Bioc packages as **single composable units** at the chain level, not as 100-step chains themselves.

## 5. Hub workflow re-use suggests minimum viable "expansion set"

If the curated catalog reuses 6 hub workflows across 17+ chains, then a small list of **anchor workflows** is doing most of the chain-anchoring work. To extend coverage without writing 100 new chains, we'd want to:

1. Identify the next tier of high-affinity workflows (catalog members that the LLM repeatedly proposes, even without curation).
2. Surface them as "promotable to curated chain" candidates.
3. Curate composed chains involving them.

This is the L1 ↔ L2 promotion path mentioned in the design doc, but with concrete starter material.

Candidates worth promoting today (based on per-pattern catalog evidence):
- `edge_timecourse_de_analysis` — anchors `time_series_longitudinal` (no curated chain yet)
- `bacon_multiple_sets_and_meta_analysis` — anchors `cross_cohort_replication`
- `piano_consensus_gsa_scoring` — anchors `multi_method_consensus`
- `scrapper_multimodal_rna_adt_analysis` — anchors `multi_omics_integration` for scRNA+ADT
- `PhyKIT Phylogenetic Metrics` — anchors `resampling_uncertainty`

Each one of these could seed 1–3 curated chains and we'd have natural mode lifts on the calibration eval.

## 6. The curated-chain placeholder problem, quantified

74 step transitions × 2 endpoints = 148 step references. Of those:

- **65 are placeholders** that don't exist in `workflows` (e.g., `pocket_detection_druggability`, `biomarker_feature_selection`, `case_report`).
- **83 reference real catalog workflows**.
- **16 unique catalog workflow names** are actually referenced.

So even our curated chains are mostly storytelling: we hand-wrote step ordering using descriptive placeholder names, but only 16 of them are grounded enough to actually execute through to a real workflow.

**Implication for the chain executor**: at most, 1-2 of our 29 curated chains can run end-to-end as written without manual workflow substitution. The other 27+ would need each placeholder stage resolved to a real catalog workflow at run time — which is exactly what the LLM composer does. So the L1 path and L2 path are less distinct than the design framing suggested. **L1 today is more "chain skeleton + L2 substitution per step" than "deterministic curated chain.**

## Implications, restated

1. **Cross-domain chaining is the unsolved problem.** We have 3 cross-domain transitions in the curated catalog, against a catalog that contains 21+ distinct domains. The pattern library + L2 LLM composer is the only path that has any chance of covering this space.

2. **The curated chain catalog is closer to a "named-pattern lookup table" than a "ready-to-execute chain set."** 16 grounded workflows × 29 chains × placeholder slots = a tree-of-templates, not a tree-of-runs.

3. **High-volume catalog signals aren't usable as proxies for capability:**
   - `tools_used` reflects dependencies, not methods.
   - `step_count` reflects function count, not pipeline length.
   - Per-domain workflow counts mix package indexing with workflow indexing.

4. **Hub workflows are the smallest investment with the highest leverage.** Promoting `edge_timecourse_de_analysis`, `bacon_*`, `piano_*` etc. to anchor 5 new curated chains would directly close calibration gaps (`time_series_longitudinal`, the biomarker-validation case) without needing indexer surgery.

5. **The L1/L2/L3 framing needs refinement.** L1 isn't really deterministic curated-chain pass-through — it's pass-through *of a chain that mostly contains placeholders*. The composer always does L2-style substitution on those placeholders. We should be honest about this in the design doc.

## Reproducibility

```bash
cd /home/yzhang/biomate/.claude/worktrees/agent-aaf4e393b5ea5b614
# Counts produced by an ad-hoc Python script run against the live DB;
# move into chain_composer/catalog_audit.py as a `--connectivity` flag if
# this becomes a recurring need.
```

## What this changes about earlier recommendations

The "build LLM-judge domain reclassification of 636 `general`" item is still valuable but lower priority than:

- **Author curated chains around the 5 hub-candidates from §5.** That's the highest-leverage investment per minute right now.
- **Update design doc** to honestly reflect §5: L1 isn't deterministic pass-through; it's pattern-+-placeholder lookup with L2 substitution.
- **Verifier upgrade**: when LLM substitutes a real workflow for a placeholder step name in a curated chain, record the substitution → this is exactly the L1↔L2 promotion data we'd need.
