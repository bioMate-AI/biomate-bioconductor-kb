---
name: bioconductor-gsva
description: Gene Set Variation Analysis (GSVA) is a non-parametric, unsupervised method for estimating variation of gene set enrichment through the samples of a expression data set. GSVA performs a change in coordinate systems, transforming the data fr
when_to_use: Use when: Sample-Wise Pathway Scoring: Calculating sample-specific pathway enrichment scores from a gene expression matrix using gsva.; Dimensionality Reduction: Transforming a high-dimensional gene-by-sample matrix into a lower-dimensional pathway-by-sample matrix for downstream analysis.; Method-Specific Enrichment: Applying specific single-sample enrichment methods like PLAGE, z-score, or ssGSEA using pl. Not for: For Simple Differential Expression: For simple differential expression of individual genes, use edgeR because it is designed for gene-level count data modeling rather than gene set enrichment.; For Purely Managing Gene Sets: For purely importing and 
user-invocable: false
---

# GSVA

## When to Use
- **Sample-Wise Pathway Scoring**: Calculating sample-specific pathway enrichment scores from a gene expression matrix using `gsva`.
- **Dimensionality Reduction**: Transforming a high-dimensional gene-by-sample matrix into a lower-dimensional pathway-by-sample matrix for downstream analysis.
- **Method-Specific Enrichment**: Applying specific single-sample enrichment methods like PLAGE, z-score, or ssGSEA using `plageParam`, `zscoreParam`, or `ssgseaParam`.

## When NOT to Use
- **For Simple Differential Expression**: For simple differential expression of individual genes, use `edgeR` because it is designed for gene-level count data modeling rather than gene set enrichment.
- **For Purely Managing Gene Sets**: For purely importing and managing gene set collections without analysis, use `GSEABase` because it provides dedicated classes like `GeneSetCollection` and functions like `getGmt`.

## Data Requirements
- **Expression Matrix**: A normalized gene expression matrix, an `ExpressionSet`, or a `SummarizedExperiment` object.
- **Gene Sets**: A `list` object of gene identifiers or a `GeneSetCollection` object.

## Key Parameters
- **kcdf** ("auto"): Kernel consensus density estimation; use `"Gaussian"` for continuous data or `"Poisson"` for integer counts.
- **kcdfNoneMinSampleSize** (200): Minimum sample size at which the empirical cumulative distribution function is estimated directly without a kernel.
- **tau** (1): Exponent defining the weight of the tail in the random walk.
- **maxDiff** (TRUE): Logical flag specifying whether to calculate the enrichment score as the magnitude difference between the largest positive and negative random walk deviations.
- **absRanking** (FALSE): Logical flag implying whether a modified Kuiper statistic is used.
- **sparse** (FALSE): Logical flag used when the input expression data is stored in a sparse matrix.
- **minSize** (1): Minimum size of gene sets to be considered.
- **maxSize** (Inf): Maximum size of gene sets to be considered.

## Best Practices
- **Match Identifiers**: Ensure gene identifiers between the expression data matrix and the gene sets belong to the same standard nomenclature to allow `mapIdentifiers` to work.
- **Set the Correct Kernel**: Use `kcdf="Poisson"` when providing RNA-seq integer count data directly to `gsvaParam`.
- **Import GMTs Safely**: Use `readGMT` to import gene sets from GMT files, as it handles duplicated gene set names better than base R functions.

## Common Pitfalls
- **Providing Raw Counts with Gaussian Kernel**: Running GSVA on raw RNA-seq counts without changing the kernel. Fix: Set `kcdf="Poisson"` in `gsvaParam` when using integer counts.
- **Identifier Mismatch**: Gene identifiers do not match between the expression matrix and gene sets. Fix: Provide data using specialized containers (like `ExpressionSet` or `SummarizedExperiment`) so GSVA can automatically map identifiers.
- **Duplicated Gene Set Names**: Duplicated gene set names in GMT files causing errors with standard import functions. Fix: Use the `readGMT` function which deduplicates gene set names by default.

## Alternatives
- `GSEABase`: For foundational gene set data structures and basic GMT file importing.
- `qusage`: Provides alternative functions like `read.gmt` for reading gene sets.
- `edgeR`: For gene-level differential expression analysis using log-CPM units.

## Citations
- Hänzelmann S, Castelo R, Guinney J. "GSVA: gene set variation analysis for microarray and RNA-seq data." BMC Bioinformatics, 2013.
- Barbie et al. "Systematic RNA interference reveals that oncogenic KRAS-driven cancers require TBK1." Nature, 2009.

## References
- Homepage: https://bioconductor.org/packages/GSVA
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/GSVA/inst/doc/GSVA.html
