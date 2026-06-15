---
name: bioconductor-deconvr
description: This package provides a collection of functions designed for analyzing deconvolution of the bulk sample(s) using an atlas of reference omic signature profiles and a user-selected model. Users are given the option to create or extend a reference atlas and,also simulate the desired size of the bulk signature profile of the reference cell types.The package includes the cell-type-specific methylation atlas and, Illumina Epic B5 probe ids that can be used in deconvolution. Additionally,we included BS
when_to_use: Use when: This package provides a collection of functions designed for analyzing deconvolution of the bulk sample(s) using an atla; output.lines=10 using findSignatures; output.lines=10 using BSmeth2Probe, deconvolute; output.lines=10 using simulateCellMix, findSignatures; output.lines=10 using simulateCellMix, findSignatures; Single-cell RNA-seq analysis (deconvR). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# deconvR

## Workflows

### Standard Workflow

Map WGBS methylation data to Illumina probe IDs and predict cell-type proportions using a reference atlas.

```r
library(deconvR)
data("HumanCellTypeMethAtlas")
data("IlluminaMethEpicB5ProbeIDs")

# Load WGBS data
load(system.file("extdata", "WGBS_GRanges.rda", package = "deconvR"))

# Map WGBS genomic coordinates to probe IDs
mapped_WGBS_data <- BSmeth2Probe(probe_id_locations = IlluminaMethEpicB5ProbeIDs, 
                                 WGBS_data = WGBS_GRanges,
                                 multipleMapping = TRUE,
                                 cutoff = 10)

# Perform deconvolution
deconvolution <- deconvolute(reference = HumanCellTypeMethAtlas, 
                             bulk = mapped_WGBS_data)
deconvolution$proportions
```
*Input is a GRanges object of WGBS data and a probe ID location reference; output is a dataframe of predicted cell-type proportions.*

### Atlas Extension And Signature Generation

Extend an existing reference atlas with new sample data or construct tissue-specific CpG/DMP signature matrices.

```r
library(deconvR)
data("HumanCellTypeMethAtlas")

# Simulate new sample data
samples <- simulateCellMix(3, reference = HumanCellTypeMethAtlas)$simulated

# Prepare sample metadata
sampleMeta <- data.table::data.table("Experiment_accession" = colnames(samples)[-1],
                                     "Biosample_term_name" = "new cell type")

# Extend the reference atlas
extended_matrix <- findSignatures(samples = samples, 
                                 sampleMeta = sampleMeta, 
                                 atlas = HumanCellTypeMethAtlas,
                                 IDs = "IDs")
```
*Inputs are a sample matrix, metadata table, and reference atlas; output is an extended reference matrix.*

## When to Use
- Predicting cell-type proportions from bulk DNA methylation data using `deconvolute`.
- Mapping WGBS genomic coordinates to Illumina probe IDs using `BSmeth2Probe`.
- Simulating bulk omic mixtures with known proportions using `simulateCellMix`.
- Extending a reference atlas or generating tissue-specific CpG/DMP signatures using `findSignatures`.

## When NOT to Use
- For single-cell RNA-seq clustering or cell-type annotation, use `Seurat` or `scran` because `deconvR` is designed for bulk deconvolution.
- For differential methylation locus identification without deconvolution, use `methylKit` because `deconvR` focuses on signature-based deconvolution.

## Data Requirements
- **Reference Atlas**: A dataframe of cell types (columns) and CpG loci (rows, e.g., Illumina Probe IDs) containing methylation values between 0 and 1 (e.g., `HumanCellTypeMethAtlas`).
- **Bulk Data**: WGBS data as a `GRanges` object (e.g., `WGBS_GRanges`) or a `methylKit` object, or mapped probe-level data.
- **Metadata**: A `data.table` or `data.frame` mapping sample accessions to biosample terms.

## Key Parameters
- **probe_id_locations**: A `GRanges` object containing probe IDs and genomic coordinates.
- **WGBS_data**: A `GRanges` or `methylKit` object containing methylation values.
- **multipleMapping** (`TRUE`): Logical indicating whether to allow multiple mapping in `BSmeth2Probe`.
- **cutoff** (`10`): Minimum coverage cutoff for mapping.
- **reference**: Reference atlas dataframe used for deconvolution.
- **bulk**: Mapped bulk methylation data dataframe.
- **IDs**: Column name containing probe or gene IDs.
- **tissueSpecCpGs** (`FALSE`): Logical to construct tissue-based methylation signature matrix.

## Best Practices
- Check deconvolution performance by comparing simulated mixtures from `simulateCellMix` with `deconvolute` predictions.
- Verify that the reference matrix and bulk samples use the same identifier type (e.g., Illumina Probe IDs or Gene names).
- Use `BSmeth2Probe` to map WGBS coordinates to probe IDs before running deconvolution.
- Evaluate deconvolution quality using the partial R-squared values returned by `deconvolute`.

## Common Pitfalls
- **Mismatching ID column names**: Ensure the `IDs` parameter in `findSignatures` matches the ID column name of the reference atlas and bulk data.
- **Using unmapped WGBS coordinates directly**: Map coordinates to probe IDs first using `BSmeth2Probe` before running `deconvolute`.
- **Setting conflicting signature flags**: Ensure only one of `tissueSpecCpGs` or `tissueSpecDMPs` is set to `TRUE` as they cannot be run together.

## Alternatives
- `methylKit` for multi-sample DNA methylation analysis and differential methylation.
- `minfi` for analyzing Illumina Infinium Methylation Cleanup and normalization.
- `Seurat` for single-cell level expression analysis and integration.

## Citations
- Moss, J. et al. (2018). Comprehensive human cell-type methylation atlas reveals origins of circulating cell-free DNA in health and disease. Nature communications, 9(1), 1-12.

## References
- Homepage: bioconductor.org/packages/deconvR
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/deconvR/inst/doc/deconvR.html
