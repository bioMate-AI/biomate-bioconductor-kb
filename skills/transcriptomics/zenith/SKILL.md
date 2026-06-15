---
name: bioconductor-zenith
description: Zenith performs gene set analysis on the result of differential expression using linear (mixed) modeling with dream by considering the correlation between gene expression traits.  This package implements the camera method from the limma package proposed by Wu and Smyth (2012).  Zenith is a simple extension of camera to be compatible with linear mixed models implemented in variancePartition::dream().
when_to_use: Use when: Example usage of zenith on GEUVAIDIS RNA-seq; Example usage of zenith on RNA-seq; Differential expression analysis (zenith); Data normalization and preprocessing (zenith); Quality control and preprocessing (zenith). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# Zenith

## Workflows

### Standard Workflow

Perform gene set enrichment analysis on differential expression results from a linear mixed model fit with dream and visualize the results.

```r
library(zenith)
library(edgeR)
library(variancePartition)
library(tweeDEseqCountData)
library(kableExtra)

# 1. Filter low-expressed genes
data(pickrell)
geneCounts = exprs(pickrell.eset)
df_metadata = pData(pickrell.eset)
dsgn = model.matrix(~ gender, df_metadata)
keep = filterByExpr(geneCounts, dsgn, min.count=5)

# 2. Compute library size normalization
dge = DGEList(counts = geneCounts[keep,])
dge = calcNormFactors(dge)

# 3. Estimate precision weights
vobj = voomWithDreamWeights(dge, ~ gender, df_metadata)

# 4. Fit linear (mixed) model
fit = dream(vobj, ~ gender, df_metadata)
fit = eBayes(fit)

# 5. Load gene sets and run zenith
msdb.gs = get_MSigDB("H", to="ENSEMBL")
res.gsa = zenith_gsa(fit, msdb.gs, 'gendermale', progressbar=FALSE)
plotZenithResults(res.gsa)
```
*Input: Raw RNA-seq counts and sample metadata. Output: A data frame of gene set enrichment statistics and a heatmap visualization of the top results.*

## When to Use
- To perform gene set enrichment analysis on differential expression results generated from linear (mixed) models using `variancePartition::dream()`.
- To account for correlation between gene expression traits by extending the `camera` method from `limma` to linear mixed models.
- To easily fetch and cache gene sets from MSigDB (using `get_MSigDB`) or Gene Ontology (using `get_GeneOntology`).

## When NOT to Use
- For simple fixed-effect designs without random effects or sample correlation; standard `limma::camera` is sufficient.
- If you are not using `variancePartition::dream` for differential expression; `zenith_gsa` is specifically designed to take the output of `dream()`.

## Data Requirements
- A fitted model object from `variancePartition::dream()` that has been processed with `limma::eBayes()`.
- A `GeneSetCollection` object containing gene sets (e.g., loaded via `get_MSigDB` or `get_GeneOntology`).
- Gene identifiers in the gene sets must match the rownames of the fitted model (e.g., both using ENSEMBL or SYMBOL).

## Key Parameters
- **to** ("ENSEMBL"): Target gene identifier type (e.g., "ENSEMBL", "SYMBOL", "ENTREZ") in `get_MSigDB` or `get_GeneOntology`.
- **progressbar** (FALSE): Logical indicating whether to show a progress bar during `zenith_gsa` execution.
- **coef** ('gendermale'): The coefficient/contrast in the fitted model to evaluate for gene set enrichment.

## Best Practices
- Filter out low-expressed genes using `edgeR::filterByExpr` to improve statistical power and model stability.
- Estimate precision weights using `variancePartition::voomWithDreamWeights` to account for the mean-variance relationship in RNA-seq count data.
- Use `plotZenithResults` to visualize the top gene set enrichment results across coefficients or cell types.

## Common Pitfalls
- Gene identifier mismatch: Ensure the gene ID type specified in `get_MSigDB(..., to=...)` matches the ID type used as rownames in the expression matrix and the `dream` fit.
- Running on raw counts: Always normalize counts using `calcNormFactors` and apply `voomWithDreamWeights` before fitting models with `dream`.

## Alternatives
- `limma::camera` for fixed-effect linear models.
- `EnrichmentBrowser::getGenesets` for loading alternative gene set databases like KEGG or Enrichr.

## Citations
- Hoffman G (2026). Zenith: Gene set analysis for linear mixed models. R package.
- Wu D, Smyth GK (2012). Camera: a competitive gene set test accounting for inter-gene correlation. Nucleic Acids Research.

## References
- Homepage: bioconductor.org/packages/zenith
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/zenith/inst/doc/zenith.html
