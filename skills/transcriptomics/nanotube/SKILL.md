---
name: bioconductor-nanotube
description: NanoTube includes functions for the processing, quality control, analysis, and visualization of NanoString nCounter data. Analysis functions include differential analysis and gene set analysis methods, as well as postprocessing steps to help understand the results. Additional functions are included to enable interoperability with other Bioconductor NanoString data analysis packages.
when_to_use: Use when: NanoTube Vignette; Differential expression analysis (NanoTube); Quality control and preprocessing (NanoTube). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# NanoTube

## Workflows

### Standard Workflow

```r
library(NanoTube)

# Process and normalize NanoString data
dat <- processNanostringData(
  nsFiles = example_data,
  sampleTab = sample_info,
  idCol = "RCC_Name",
  groupCol = "Sample_Diagnosis",
  normalization = "nSolver"
)

# Run differential expression analysis using Limma
limmaResults <- runLimmaAnalysis(dat, base.group = "None")

# Generate volcano plot of differential expression results
deVolcano(limmaResults, plotContrast = "Autoimmune.retinopathy")

# Run gene set enrichment analysis
fgseaResults <- limmaToFGSEA(limmaResults, gene.sets = ExamplePathways)
```
Input: RCC files or tabular expression data, sample metadata.
Output: Normalized ExpressionSet, differential expression statistics, volcano plots, and GSEA results.

## When to Use
- Processing, quality control, and normalization of NanoString nCounter data (RCC files or tabular counts) using `processNanostringData`.
- Performing differential expression analysis on NanoString data using `runLimmaAnalysis`.
- Performing Gene Set Enrichment Analysis (GSEA) directly from differential expression results using `limmaToFGSEA` or `nsdiffToFGSEA`.
- Visualizing NanoString data quality using `positiveQC`, `negativeQC`, `nanostringPCA`, or RLE plots.

## When NOT to Use
- For high-throughput RNA-seq data, use standard pipelines like `DESeq2` or `edgeR`.
- For microarray data, use `limma` directly.

## Data Requirements
- Raw NanoString RCC files or a CSV/TXT expression matrix.
- A sample metadata CSV file containing sample characteristics and matching file names.

## Key Parameters
- **normalization** ("nSolver"): Normalization method in `processNanostringData` ("nSolver", "RUVIII", "RUVg", or "none").
- **bgType** ("threshold"): Method for background assessment ("threshold" or "t.test").
- **bgPVal** (0.01): P-value threshold for the t-test background method.
- **skip.housekeeping** (FALSE): Whether to skip housekeeping normalization.
- **n.unwanted** (1): Number of dimensions of unwanted variation to remove in RUVg/RUVIII.
- **base.group** (NULL): Control group for contrast in `runLimmaAnalysis`.

## Best Practices
- Perform quality control checks on positive controls using `positiveQC` and negative controls using `negativeQC` before downstream analysis.
- Verify that positive scaling factors are between 0.3 and 3, and R-squared values are greater than 0.95.
- Check housekeeping normalization scale factors to ensure they are within the recommended 0.1-10 range.

## Common Pitfalls
- Mismatched sample names between RCC files and the sample metadata table; specify `idCol` in `processNanostringData` to ensure correct merging.
- Including empty factor levels in the design matrix; drop them using `droplevels()` before analysis.

## Alternatives
- `NanoStringDiff` for differential analysis using a generalized linear model.
- `limma` for general linear modeling.
- `RUVSeq` for removing unwanted variation.

## Citations
- Lundy et al. 2018 (referenced in vignette)
- Ritchie et al. 2015 (limma reference)

## References
- Homepage: bioconductor.org/packages/NanoTube
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/NanoTube/inst/doc/NanoTube.html
