---
license: cc-by-4.0
---
# RealBio Benchmark — cross_domain_routing

*Part of **RealBio Benchmark**: real-world execution benchmarks for bioinformatics AI agents (see the suite README).*

**Task.** Given a natural-language analysis request, name the single correct WORKFLOW that should run it (targets are public nf-core pipeline names where applicable). Credit for acceptable_alts.

**Items.** 200  ·  **Ground-truth field(s).** `correct_workflow`  ·  **Scoring.** objective (see ../score.py) — no LLM judge required.

Any system can run this benchmark and be scored on the same items. Targets are public workflow names (mostly nf-core), so this is a real, catalog-neutral routing task any system can attempt.



## Ground-truth corrections (2026-10-25, documented per benchmark-accuracy policy)

Item-level error analysis (`docs/20261025_BENCHMARK_ERROR_ANALYSIS_ROOTCAUSE.md`) found three items whose
`acceptable_alts` were empty but where a second workflow is genuinely correct for the query. These were
added (gold `correct_workflow` unchanged; the alt is simply also credited):

- **sc_007** "filter empty droplets and doublets" → added `scrna_doublet_qc`. The gold `nf-core/scrnaseq`'s
  own description states it is "NOT for filtering dead cells / doublets"; `scrna_doublet_qc` is the
  doublet-QC workflow and is a correct answer for a doublet-filtering request.
- **sc_022** "subcellular RNA molecule detection, not spot-based, 300 gene panel" → added
  `nf-core/spatialxe`. The query describes imaging-based subcellular spatial transcriptomics with a targeted
  gene panel, which fits both MERFISH (`merfish_spatial_analysis`, gold) and Xenium (`nf-core/spatialxe`).
- **mo_009** "ADT denoising and normalization for surface protein markers in CITE-seq" → added
  `scrapper_multimodal_rna_adt_analysis`, which performs CITE-seq ADT denoising/normalization alongside the
  gold `cite_seq_preprocessing`.

Not changed: `sc_011` (query explicitly names "Space Ranger", which the gold `nf-core/spatialvi` pipeline
runs and `spatial_visium_banksy` does not). Genuine model errors (e.g. 10x-short-read queries mis-routed to
`nf-core/scnanoseq`) were NOT papered over with alts — those are fixed at the source (workflow descriptions,
`scripts/fix_routing_descriptions_20261025.py`).
