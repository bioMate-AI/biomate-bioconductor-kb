---
name: bioconductor-msstatslip
description: Tools for LiP peptide and protein significance analysis. Provides functions for summarization, estimation of LiP peptide abundance, and detection of changes across conditions. Utilizes functionality across the MSstats family of packages.
when_to_use: Use when: MSstatsLiP Workflow: An example workflow and analysis of the MSstatsLiP package; MSstatsLiP Proteolytic Workflow; Differential expression analysis (MSstatsLiP); Proteomics quantification (MSstatsLiP); Data normalization and preprocessing (MSstatsLiP). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# MSstatsLiP

## Workflows

### Proteolytic Resistance Analysis

```r
library(MSstatsLiP)

# Calculate proteolytic resistance ratios and perform differential analysis
Accessibility <- calculateProteolyticResistance(
  MSstatsLiP_Summarized, 
  fasta_file, 
  differential_analysis = TRUE
)

# Plot proteolytic resistance results as a barcode along the protein sequence
ResistanceBarcodePlotLiP(
  Accessibility, 
  fasta_file, 
  which.prot = "P16622", 
  which.condition = "F1", 
  differential_analysis = TRUE, 
  which.comp = "F1 vs F2", 
  address = FALSE
)
```
Input: Summarized LiP-MS and TrP-MS datasets (`MSstatsLiP_Summarized`) and a FASTA file (`fasta_file`).
Output: Proteolytic resistance ratios and sequence-aligned barcode plots.

### Standard Workflow

```r
library(MSstatsLiP)

# Convert raw Spectronaut data to MSstatsLiP format
msstats_data <- SpectronauttoMSstatsLiPFormat(
  raw_lip, 
  fasta_file, 
  raw_prot
)

# Summarize the preprocessed data
MSstatsLiP_Summarized <- dataSummarizationLiP(
  msstats_data, 
  normalization.LiP = "equalizeMedians"
)

# Perform group comparison modeling
MSstatsLiP_model <- groupComparisonLiP(MSstatsLiP_Summarized)
```
Input: Raw Spectronaut LiP and TrP datasets, and a FASTA file.
Output: Preprocessed, summarized, and modeled LiP-MS and TrP-MS datasets.

## When to Use
- Analyzing Limited Proteolysis-coupled Mass Spectrometry (LiP-MS) datasets alongside Trypsin-only control (TrP-MS) datasets.
- Preprocessing Spectronaut exports using `SpectronauttoMSstatsLiPFormat`.
- Performing differential analysis of proteolytic resistance patterns across conditions using `calculateProteolyticResistance` and `groupComparisonLiP`.
- Visualizing peptide-level proteolytic resistance changes along a protein sequence using `ResistanceBarcodePlotLiP`.

## When NOT to Use
- For standard bottom-up shotgun proteomics data without limited proteolysis, use `MSstats` directly.
- For differential expression analysis of RNA-seq data, use packages like `limma`, `edgeR`, or `DESeq2`.

## Data Requirements
- Raw LiP-MS and TrP-MS datasets (e.g., Spectronaut exports) containing columns like `PG.ProteinAccessions`, `PEP.GroupingKey`, `EG.Qvalue`, and `F.PeakArea`.
- A FASTA file containing the protein sequences of interest.

## Key Parameters
- **normalization.LiP** ("equalizeMedians"): Normalization method for LiP data in `dataSummarizationLiP`.
- **differential_analysis** (TRUE): Whether to perform differential analysis in `calculateProteolyticResistance`.
- **which.prot** (NULL): Protein accession to plot in `ResistanceBarcodePlotLiP`.
- **which.condition** (NULL): Condition to plot in `ResistanceBarcodePlotLiP`.
- **address** (FALSE): Whether to save the plot to a file or display it in `ResistanceBarcodePlotLiP`.

## Best Practices
- Filter out half-tryptic (HT) peptides and retain only fully tryptic (FT) peptides for proteolytic resistance analysis using `calculateTrypticity`.
- Ensure that the Condition nomenclature is identical in both LiP and TrP datasets before summarization.
- Ensure unique BioReplicate nomenclature for case-control experiments.

## Common Pitfalls
- Mismatched condition names between LiP and TrP datasets, causing errors in summarization or modeling; verify using `unique(msstats_data[["LiP"]]$Condition) %in% unique(msstats_data[["TrP"]]$Condition)`.
- High memory usage during summarization; clear memory cache using `rm()` and `gc()` if needed.

## Alternatives
- `MSstats` for standard proteomics without limited proteolysis.
- `limma` for general linear modeling of expression data.

## Citations
- Cappelletti et al., 2021 (referenced in vignette text)

## References
- Homepage: bioconductor.org/packages/MSstatsLiP
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/MSstatsLiP/inst/doc/MSstatsLiP_Workflow.html
