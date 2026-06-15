---
name: bioconductor-mirtarrnaseq
description: mirTarRnaSeq R package can be used for interactive mRNA miRNA sequencing statistical analysis. This package utilizes expression or differential expression mRNA and miRNA sequencing results and performs interactive correlation and various GLMs (Regular GLM, Multivariate GLM, and Interaction GLMs ) analysis between mRNA and miRNA expriments. These experiments can be time point experiments, and or condition expriments.
when_to_use: Use when: mirTarRnaSeq; Differential expression analysis (mirTarRnaSeq). Not for: Requires R ≥ 4.1.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# mirTarRnaSeq

## Workflows

### Mirna Mrna Correlation Multi Timepoint

Identify significant miRNA-mRNA correlations across three or more time points using fold change data and background distribution comparisons.

```r
library(mirTarRnaSeq)

# 1. Parse fold changes and filter mRNAs/miRNAs
mrna <- one2OneRnaMiRNA(mrna_files, pthreshold = 0.05)$foldchanges
mirna <- one2OneRnaMiRNA(mirna_files)$foldchanges

# 2. Calculate Pearson correlation
corr_0 <- corMirnaRna(mrna, mirna, method = "pearson")

# 3. Generate background correlation distribution
outs <- sampCorRnaMirna(mrna, mirna, method = "pearson", Shrounds = 100, Srounds = 1000)

# 4. Plot correlation density
mirRnaDensityCor(corr_0, outs)

# 5. Identify significant correlations
sig_corrs <- threshSig(corr_0, outs, pvalue = 0.05)

# 6. Retrieve species-specific miRanda predictions
miRanda <- getInputSpecies("Mouse", threshold = 150)

# 7. Intersect and visualize results
results <- miRandaIntersect(sig_corrs, outs, mrna, mirna, miRanda)
p <- mirRnaHeatmap(results$corr, upper_bound = -0.99)
```
*Input: Multi-timepoint mRNA and miRNA fold change files. Output: Heatmap and list of significant miRNA-mRNA correlations intersected with miRanda predictions.*

### Mirna Mrna Relationship Two Timepoint

Identify significant miRNA-mRNA fold change differences between two time points compared to a background distribution.

```r
library(mirTarRnaSeq)

# 1. Parse fold changes and filter mRNAs
mrna <- one2OneRnaMiRNA(mrna_files, pthreshold = 0.05)$foldchanges
mirna <- one2OneRnaMiRNA(mirna_files)$foldchanges

# 2. Estimate miRNA-mRNA fold change differences
inter0 <- twoTimePoint(mrna, mirna)

# 3. Generate background distribution of fold change differences
outs <- twoTimePointSamp(mrna, mirna, Shrounds = 10)

# 4. Retrieve species-specific miRanda target predictions
miRanda <- getInputSpecies("Mouse", threshold = 140)

# 5. Identify relationships below a p-value threshold
sig_InterR <- threshSigInter(inter0, outs)

# 6. Intersect significant relationships with miRanda predictions
results <- mirandaIntersectInter(sig_InterR, outs, mrna, mirna, miRanda)

# 7. Format final results and draw plots
final_results <- finInterResult(results)
drawInterPlots(mrna, mirna, final_results)
mirRnaHeatmapDiff(results$corrs, upper_bound = 9.9)
```
*Input: Two-timepoint mRNA and miRNA fold change files. Output: Fold change plots and heatmap of significant miRNA-mRNA differences.*

### Standard Workflow

Identify miRNA-mRNA target interactions in a cohort using various GLM regression models integrated with miRanda predictions.

```r
library(mirTarRnaSeq)

# 1. Retrieve species-specific miRanda target predictions
miRanda <- getInputSpecies("Epstein_Barr", threshold = 140)

# 2. Filter mRNA data to keep only predicted targets
DiffExpmRNASub <- miRanComp(DiffExp, miRanda)

# 3. Combine mRNA and miRNA data
miRNA_select <- c("ebv-mir-BART9-5p")
Combine <- combiner(DiffExp, miRNAExp, miRNA_select)
geneVariant <- geneVari(Combine, miRNA_select)

# 4. Run univariate GLM models (e.g., Poisson)
j <- runModel(`LMP-1` ~ `ebv-mir-BART9-5p`, Combine, model = glm_poisson(), scale = 100)
print(modelTermPvalues(j))

# 5. Run models across all combinations with a specific family
blaGaus <- runModels(Combine, geneVariant, miRNA_select, family = glm_gaussian(), scale = 100)

# 6. Run all-to-all combinations using multi-model GLM
All_miRNAs_run <- runAllMirnaModels(
  mirnas = rownames(miRNAExp)[1:5],
  DiffExpmRNA = DiffExpmRNASub,
  DiffExpmiRNA = miRNAExp,
  miranda_data = miRanda,
  prob = 0.75,
  cutoff = 0.05,
  fdr_cutoff = 0.1,
  method = "fdr",
  family = glm_multi(),
  scale = 2,
  mode = "multi"
)
```
*Input: mRNA and miRNA expression matrices. Output: Fitted GLM models and identified significant miRNA-mRNA target interactions.*

## When to Use
- To perform regression analysis (Gaussian, Poisson, Negative Binomial, Zero-Inflated) between miRNA and mRNA expression across sample cohorts using `runModels()`.
- To identify significant miRNA-mRNA correlations across 3 or more time points using `corMirnaRna()` and `sampCorRnaMirna()`.
- To compare miRNA-mRNA fold change differences between two time points using `twoTimePoint()` and `twoTimePointSamp()`.
- To filter and intersect statistical results with species-specific miRanda target predictions using `getInputSpecies()` and `miRanComp()`.

## When NOT to Use
- For predicting physical miRNA-mRNA binding sites from sequence data alone; use standalone `miRanda` or `TargetScan` because `mirTarRnaSeq` requires expression data to perform statistical association.
- For differential expression analysis of RNA-seq data; use `DESeq2` or `edgeR` because `mirTarRnaSeq` expects pre-computed expression matrices or fold changes.

## Data Requirements
- mRNA and miRNA expression matrices (TPM, RPKM, or normalized counts) with samples as columns and gene/miRNA names as rows.
- For time-point analyses, pre-computed fold change tables from differential expression analysis.
- Species-specific miRanda target prediction files (supported species include "Human", "Mouse", "Epstein_Barr", etc.).

## Key Parameters
- **threshold** (140): Score threshold for filtering miRanda predictions in `getInputSpecies()`.
- **scale** (100): Scaling factor applied to expression values during GLM modeling.
- **family** (`glm_gaussian()`): Statistical distribution family for GLM modeling (e.g., `glm_poisson()`, `glm_nb()`, `glm_zeroinfl()`, `glm_multi()`).
- **mode** ("multi"): Mode for running multi-model GLMs ("multi" or "inter").
- **pthreshold** (0.05): P-value threshold for filtering mRNAs in `one2OneRnaMiRNA()`.
- **Shrounds** (100): Number of shuffling rounds for generating background distributions.

## Best Practices
- Normalize both mRNA and miRNA expression matrices (e.g., using TPM or z-score normalization via `tzTrans()`) before running regression models.
- Compare Akaike Information Criterion (AIC) values across different GLM families (Gaussian, Poisson, Negative Binomial) to select the best-fitting model for your data.
- Filter the mRNA expression matrix using `miRanComp()` prior to running all-to-all regressions to reduce computational time.

## Common Pitfalls
- *High computational time*: Running all-to-all regressions on unfiltered genome-wide mRNA matrices is extremely slow. Fix by filtering mRNAs to keep only predicted targets of selected miRNAs using `miRanComp()`.
- *Incompatible sample names*: If sample names (column names) do not match exactly between mRNA and miRNA expression matrices, `combiner()` will fail. Fix by aligning column names before analysis.

## Alternatives
- `multiMiR` for retrieving validated and predicted miRNA-target interactions from multiple databases.
- `SPONGE` for sparse partial correlation and miRNA-mRNA competitive endogenous RNA (ceRNA) networks.
- `DESeq2` / `edgeR` for standard differential expression analysis of mRNA and miRNA.

## Citations
- Movassagh et al. 2019, Scientific Reports (for EBV stomach cancer dataset)

## References
- Homepage: https://bioconductor.org/packages/mirtarrnaseq
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/mirtarrnaseq/inst/doc/mirTarRnaSeq.html
