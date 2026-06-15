---
name: bioconductor-busseq
description: BUSseq R package fits an interpretable Bayesian hierarchical model---the Batch Effects Correction with Unknown Subtypes for scRNA seq Data (BUSseq)---to correct batch effects in the presence of unknown cell types. BUSseq is able to simultaneously correct batch effects, clusters cell types, and takes care of the count data nature, the overdispersion, the dropout events, and the cell-specific sequencing depth of scRNA-seq data. After correcting the batch effects with BUSseq, the corrected value ca
when_to_use: Use when: BUSseq R package fits an interpretable Bayesian hierarchical model---the Batch Effects Correction with Unknown Subtypes; data preparation1 using assay, unlist; BUSgibbs using BUSseq_MCMC; Output extract using assay; Celltypes using celltypes; BatchEffects using location_batch_effects, overdispersions. Not for: Requires raw count data (not normalized values); Requires R ≥ 3.6 and Bioconductor ≥ 3.16
user-invocable: false
---

# BUSseq

## Workflows

### Standard Workflow

Correct batch effects, cluster unknown cell types, identify intrinsic genes, and obtain batch-corrected expression data from multi-batch scRNA-seq count data.

```r
library(BUSseq)
library(SingleCellExperiment)

# 1. Read user input files and prepare data
CountData <- assay(BUSseqfits_example, "counts")
batch_ind <- unlist(colData(BUSseqfits_example))

sce_input <- SingleCellExperiment(
  assays = list(counts = CountData),
  colData = DataFrame(Batch_ind = factor(batch_ind))
)

# 2. Conduct MCMC sampling and posterior inference
BUSseqfits_res <- BUSseq_MCMC(
  ObservedData = sce_input, 
  seed = 1234, 
  n.cores = 2,
  n.celltypes = 4, 
  n.iterations = 500
)

# 3. Extract the imputed read counts, estimated cell types, and batch effects
Imputed_count <- assay(BUSseqfits_res, "imputed_data")
celltyes_est <- celltypes(BUSseqfits_res)
location_batch_effects_est <- location_batch_effects(BUSseqfits_res)
overdispersion_est <- overdispersions(BUSseqfits_res)
cell_effects_est <- cell_effect_values(BUSseqfits_res)
celltype_effects_est <- celltype_effects(BUSseqfits_res)

# 4. Identify intrinsic genes that drive cell-type differences
intrinsic_gene_indicators <- intrinsic_genes_BUSseq(BUSseqfits_res)
index_intri <- which(unlist(intrinsic_gene_indicators) == "Yes")

# 5. Compute and incorporate batch-corrected read counts
BUSseqfits_res <- corrected_read_counts(BUSseqfits_res)

# 6. Visualize the raw, imputed, and corrected expression data
heatmap_data_BUSseq(BUSseqfits_res, data_type = "Raw", 
                    project_name = "BUSseq_raw_allgenes",
                    image_dir = "./heatmap")
heatmap_data_BUSseq(BUSseqfits_res, data_type = "Imputed", 
                    project_name = "BUSseq_imputed_allgenes",
                    image_dir = "./heatmap")
heatmap_data_BUSseq(BUSseqfits_res, data_type = "Corrected",
                    project_name = "BUSseq_corrected_allgenes",
                    image_dir = "./heatmap")
```
*Note: Input is a SingleCellExperiment object containing raw counts and batch indicators; output is a SingleCellExperiment object containing imputed and batch-corrected assays.*

## When to Use
- To simultaneously correct batch effects and cluster cells into unknown cell types using single-cell RNA-seq data.
- To model count data overdispersion and dropout events using a Bayesian hierarchical model.
- To identify intrinsic genes driving cell-type differences using `intrinsic_genes_BUSseq`.
- To extract cell-type-specific mean expression levels using `celltype_mean_expression` and batch-corrected counts using `corrected_read_counts`.

## When NOT to Use
- For normalized or log-transformed expression data; use packages like `limma` or `ComBat` because `BUSseq` requires raw count data to model the negative binomial distribution and dropout events.
- When the gene sets differ across batches; all input batches must have the exact same genes.

## Data Requirements
- Raw count data formatted as a `SingleCellExperiment` object with a `"counts"` assay, or as a list of matrices where each element represents a batch.
- Batch indicators provided as a factor in `colData` of the `SingleCellExperiment` object.

## Key Parameters
- **ObservedData**: A `SingleCellExperiment` object or a list representing the raw count data.
- **seed** (1234): Random seed for reproducible MCMC sampling.
- **n.cores** (2): Number of CPU cores to use for parallel computing.
- **n.celltypes** (4): The specified number of cell types present in the population.
- **n.iterations** (500): Total number of MCMC iterations.
- **n.burnin** (n.iterations/2): Number of burn-in iterations discarded before posterior inference.
- **data_type** ("Raw"): The type of data to plot in `heatmap_data_BUSseq` ("Raw", "Imputed", or "Corrected").

## Best Practices
- Ensure that the gene numbers and gene names of all batches are identical before running `BUSseq_MCMC`.
- If the number of cell types is unknown, vary `n.celltypes` and use the Bayesian Information Criterion (BIC) to select the optimal number.
- Use `corrected_read_counts` to obtain batch-corrected expression data for downstream analyses.

## Common Pitfalls
- MCMC chain fails to converge: Increase `n.iterations` and adjust `n.burnin` to ensure proper posterior sampling.
- High false discovery rate in intrinsic gene identification: Adjust the FDR threshold or increase the number of iterations to improve posterior estimation.

## Alternatives
- `Seurat` for alternative single-cell integration and clustering.
- `scater` for single-cell QC and visualization.
- `scran` for single-cell normalization and pooling.

## Citations
- Song, F., Chan, G. M., & Wei, Y. (2020). Flexible and interpretable Bayesian hierarchical model for batch effect correction in scRNA-seq.

## References
- Homepage: bioconductor.org/packages/busseq
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/busseq/inst/doc/BUSseq_user_guide.html
