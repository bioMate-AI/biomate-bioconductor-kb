---
name: bioconductor-phipdata
description: PhIPData defines an S4 class for phage-immunoprecipitation sequencing (PhIP-seq) experiments. Buliding upon the RangedSummarizedExperiment class, PhIPData enables users to coordinate metadata with experimental data in analyses. Additionally, PhIPData provides specialized methods to subset and identify beads-only samples, subset objects using virus aliases, and use existing peptide libraries to populate object parameters.
when_to_use: Use when: PhIPData: A Container for PhIP-Seq Experiments. Not for: Requires R ≥ 4.1.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# PhIPData

## Workflows

### Standard Workflow

PhIPData defines an S4 class for phage-immunoprecipitation sequencing (PhIP-seq) experiments. Buliding upon the RangedSummarizedExperiment class, PhIPData enables users to coordinate metadata with experimental data in analyses. Additionally, PhIPData provides specialized methods to subset and identify beads-only samples, subset objects using virus aliases, and use existing peptide libraries to populate object parameters.

```r
library(PhIPData)

# 1. Define dimensions and simulate data matrices
n_samples <- 5L
n_peps <- 10L
counts_dat <- matrix(sample(1:1e6, n_samples*n_peps, replace = TRUE), nrow = n_peps)
logfc_dat <- matrix(rnorm(n_samples*n_peps, mean = 0, sd = 10), nrow = n_peps)
prob_dat <- matrix(rbeta(n_samples*n_peps, shape1 = 1, shape2 = 1), nrow = n_peps)

# 2. Define metadata
peptide_meta <- data.frame(pep_id = paste0("pep_", 1:n_peps))
sample_meta <- data.frame(
  sample_name = paste0("sample", 1:n_samples), 
  group = c("ctrl", "beads", "trt", "trt", "trt")
)

# 3. Construct PhIPData object and subset beads-only samples
phip_obj <- PhIPData(counts_dat, logfc_dat, prob_dat, peptide_meta, sample_meta)
beads_only <- subsetBeads(phip_obj)
```
*Note: Inputs are parallel matrices of counts, log fold-changes, probabilities, and metadata data frames; output is a coordinated PhIPData object.*

## When to Use
- **Storing PhIP-seq experimental results**: Manage raw read counts, log2 estimated fold-changes, and enrichment probabilities in a single coordinated container.
- **Identifying and subsetting control samples**: Quickly isolate beads-only control samples using the specialized `subsetBeads()` wrapper.
- **Managing peptide libraries and virus aliases**: Query and subset specific viral species using `setAlias()`, `getAlias()`, and standard `subset()` operations.

## When NOT to Use
- **For general RNA-seq differential expression**: Use `DESeq2` or `edgeR` because `PhIPData` is specifically tailored for PhIP-seq antibody enrichment assays.
- **For single-cell transcriptomics**: Use `SingleCellExperiment` because `PhIPData` is designed for bulk phage-display sequencing experiments.
- **For mass spectrometry-based proteomics**: Use `QFeatures` or `MSnbase` because `PhIPData` is designed for high-throughput sequencing of phage libraries.

## Data Requirements
- **Assay Matrices**: Three parallel matrices of identical dimensions: `counts` (non-negative numeric values), `logfc` (log2 estimated fold-changes), and `prob` (enrichment probabilities/p-values).
- **Peptide Metadata**: A `DataFrame` or `data.frame` containing peptide identifiers, and optionally start/end positions (`pos_start`, `pos_end`).
- **Sample Metadata**: A `DataFrame` or `data.frame` containing sample names and group designations (e.g., "beads", "ctrl", "trt").

## Key Parameters
- **counts** (matrix): Raw read counts or pseudocounts for each peptide and sample.
- **logfc** (matrix): Log2 estimated fold-changes compared to negative controls.
- **prob** (matrix): Probabilities or p-values associated with enriched antibody response.
- **withDimnames** (TRUE): In `librarySize()` and `propReads()`, controls whether output vectors/matrices retain row and column names.

## Best Practices
- Ensure that the sample metadata contains a column named `group` with a `"beads"` level to enable automatic identification of beads-only control samples via `subsetBeads()`.
- Use `makeLibrary()` to save peptide annotations as reusable templates, avoiding redundant re-importing of large peptide metadata files.
- Coerce `PhIPData` objects to `DGEList` using `as(phip_obj, "DGEList")` when transitioning to edgeR for differential enrichment analysis.

## Common Pitfalls
- **Missing peptide start/end positions**: If `pos_start` and `pos_end` are missing from the peptide metadata, the constructor replaces them with 0 and prints a warning.
- **Missing required assays**: Attempting to construct a `PhIPData` object without `counts`, `logfc`, or `prob` will result in empty matrices being initialized for the missing assays.
- **Case-sensitivity in aliases**: Keys in the alias database (e.g., `"hiv"` vs `"HIV"`) are case-sensitive; ensure consistent casing when calling `getAlias()`.

## Alternatives
- **SummarizedExperiment**: For general-purpose coordinated representation of rectangular biological assay data.
- **RangedSummarizedExperiment**: For genomic-coordinate-linked assay data.
- **edgeR** (DGEList): For standard differential count analysis.

## Citations
- Chen A, Scharpf R, Ruczinski I (2026). PhIPData: A Container for PhIP-Seq Experiments. R package version 1.12.0.

## References
- Homepage: https://bioconductor.org/packages/PhIPData
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/PhIPData/inst/doc/PhIPData.html
