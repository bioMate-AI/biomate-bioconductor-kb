---
name: bioconductor-siggenes
description: Identification of differentially expressed genes and estimation of the False Discovery Rate (FDR) using both the Significance Analysis of Microarrays (SAM) and the Empirical Bayes Analyses of Microarrays (EBAM).
when_to_use: Use when: Significance Analysis of Microarrays: When identifying differentially expressed genes and estimating the False Discovery Rate (FDR) using permutation-based methods via sam().; Empirical Bayes Analysis: When computing posterior probabilities of differential expression using the Empirical Bayes Analysis of Microarrays via ebam().; Threshold Selection: When visualizing the relationship between the tu. Not for: For raw RNA-seq count data: Use DESeq2 or edgeR instead because siggenes assumes continuous, approximately normal or symmetric data and does not model negative binomial distributions.; For complex experimental designs: For complex experimental design
user-invocable: false
---

# siggenes

## When to Use
- **Significance Analysis of Microarrays**: When identifying differentially expressed genes and estimating the False Discovery Rate (FDR) using permutation-based methods via `sam()`.
- **Empirical Bayes Analysis**: When computing posterior probabilities of differential expression using the Empirical Bayes Analysis of Microarrays via `ebam()`.
- **Threshold Selection**: When visualizing the relationship between the tuning parameter (Delta), the number of significant genes, and the FDR using `delta.plot()` or `plot()`.
- **Interactive Gene Identification**: When interactively exploring specific genes on a SAM plot to retrieve locus links and symbols using `identify()`.

## When NOT to Use
- **For raw RNA-seq count data**: Use `DESeq2` or `edgeR` instead because `siggenes` assumes continuous, approximately normal or symmetric data and does not model negative binomial distributions.
- **For complex experimental designs**: For complex experimental designs with multiple nested random effects or batch correction requirements, use `limma` instead because `siggenes` is primarily optimized for simpler two-class, multi-class, or paired designs.

## Data Requirements
- **Input Format**: A matrix of normalized expression values or an `ExpressionSet` object.
- **Data Type**: Continuous, normalized values (e.g., log-transformed microarray intensities).
- **Class Labels**: A vector (`cl`) specifying the class labels for the samples (e.g., two-class unpaired, paired, or multi-class).

## Key Parameters
- **B**: An integer specifying the number of permutations to perform in `sam()`.
- **rand**: An integer seed used in `sam()` to ensure reproducible permutation results.
- **y**: The delta value (numeric) passed to `plot()` to specify the minimum probability or threshold for a gene to be called differentially expressed.
- **pos.stats**: An integer (0 to 4) in `plot()` controlling where general information (like significant genes and FDR) is plotted.
- **sig.col**: A color specification in `plot()` for highlighting significant genes (can specify different colors for up- and down-regulated genes).
- **chip**: A character string in `identify()` specifying the chip type used, allowing the function to retrieve gene symbols and locus links.

## Best Practices
- Use `plot()` on a `SAM` object without specifying a numeric `y` to generate Delta plots, which helps in choosing an appropriate delta threshold based on the FDR.
- Set the `rand` parameter in `sam()` to an integer (e.g., `rand=123`) to guarantee that your permutation-based FDR estimates are reproducible.
- Use `identify()` on an active SAM plot to interactively click on points and retrieve gene-specific annotations.
- When using `plot()` on an `EBAM` object, use the `pos.stats` argument to neatly position the summary statistics (number of significant genes and FDR) in a corner that doesn't obscure the data points.

## Common Pitfalls
- **Unstable FDR estimates**: Running `sam()` with too few permutations leads to highly variable FDR estimates; fix this by increasing the `B` parameter (e.g., `B=100` or more).
- **Missing gene annotations in plots**: Using `identify()` without providing an `ExpressionSet` or specifying the `chip` argument will fail to retrieve gene symbols; fix this by providing the correct `chip` character string.
- **Misinterpreting the Delta parameter**: Guessing a delta value blindly can result in an unacceptably high FDR; fix this by always running `delta.plot()` first to visualize the trade-off between delta, significant genes, and FDR.

## Alternatives
- **limma**: The gold standard for microarray differential expression, using moderated t-statistics which generally outperform SAM on very small datasets and handle complex linear models.
- **samr**: The original R implementation of SAM by Tibshirani et al., though `siggenes` is more tightly integrated with the Bioconductor `ExpressionSet` ecosystem.
- **DESeq2**: For count-based sequencing data, modeling the negative binomial distribution directly.

## Citations
- Tusher, V.G., Tibshirani, R., and Chu, G. (2001). Significance analysis of microarrays applied to the ionizing radiation response. *PNAS*, 98, 5116-5121.
- Efron, B., Tibshirani, R., Storey, J.D. and Tusher, V. (2001). Empirical Bayes Analysis of a Microarray Experiment. *JASA*, 96, 1151-1160.

## References
- Homepage: https://bioconductor.org/packages/siggenes
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/siggenes/inst/doc/siggenes.pdf
