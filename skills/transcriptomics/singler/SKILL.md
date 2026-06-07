---
name: bioconductor-singler
description: Performs unbiased cell type recognition from single-cell RNA sequencing data, by leveraging reference transcriptomic datasets of pure cell types to infer the cell of origin of each single cell independently.
when_to_use: Use when: Annotating unlabelled single-cell datasets using pre-labelled reference datasets (e.g., HumanPrimaryCellAtlasData()).; Propagating biological knowledge to new datasets in an automated manner without manually interpreting clusters.; Resolving closely related cell type labels using fine-tuning.. Not for: For unsupervised clustering without a reference (use scran instead because SingleR requires known labels).; For manual marker gene definition and cluster interpretation (use Seurat instead because SingleR automates this using a reference).
user-invocable: false
---

# SingleR

## When to Use
- Annotating unlabelled single-cell datasets using pre-labelled reference datasets (e.g., `HumanPrimaryCellAtlasData()`).
- Propagating biological knowledge to new datasets in an automated manner without manually interpreting clusters.
- Resolving closely related cell type labels using fine-tuning.

## When NOT to Use
- For unsupervised clustering without a reference (use `scran` instead because `SingleR` requires known labels).
- For manual marker gene definition and cluster interpretation (use `Seurat` instead because `SingleR` automates this using a reference).

## Data Requirements
- **Test dataset**: Unlogged counts are acceptable, as only ranks are used by `SingleR()`.
- **Reference dataset**: Must be normalized and log-transformed (e.g., using `normalizeRnaCounts.se()`).

## Key Parameters
- **test**: The unlabelled single-cell dataset to be annotated.
- **ref**: The pre-labelled reference dataset.
- **labels**: The cell type labels corresponding to the reference dataset.
- **assay.type.test**: The assay index or name to use from the test dataset.
- **de.method**: The marker detection mode (e.g., `"wilcox"` for single-cell references).

## Best Practices
- Perform cell-based quality control before running `SingleR()`.
- Normalize and log-transform reference datasets using `normalizeRnaCounts.se()`.
- Inspect assignment confidence using `plotScoreHeatmap()` and `plotDeltaDistribution()`.
- Remove poor-quality or ambiguous assignments using `pruneScores()`.
- Examine the expression of marker genes for each label in the test dataset using `plotMarkerHeatmap()`.

## Common Pitfalls
- Using raw counts for the reference (fix: log-transform and normalize the reference first using `normalizeRnaCounts.se()`).
- Default marker detection failing on low-coverage data (fix: use `de.method="wilcox"` to consider variance of expression across cells).
- Uncertain assignments for cells whose true label does not exist in the reference (fix: inspect per-cell deltas and use `pruneScores()` to replace low-quality assignments with `NA`).

## Alternatives
- `Seurat` (for manual marker gene definition and cluster interpretation).
- `scmap` (for projection-based single-cell annotation).

## Citations
- Aran, D., et al. 2019. "Reference-based analysis of lung single-cell sequencing reveals a transitional profibrotic macrophage." Nat. Immunol. 20 (2): 163–72.
- Grun, D., et al. 2016. "De Novo Prediction of Stem Cell Identity using Single-Cell Transcriptome Data." Cell Stem Cell 19 (2): 266–77.

## References
- Homepage: bioconductor.org/packages/SingleR
- Vignette: vignette_0_9645ffcc.txt
