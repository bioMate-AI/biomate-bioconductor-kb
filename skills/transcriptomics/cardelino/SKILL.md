---
name: bioconductor-cardelino
description: Methods to infer clonal tree configuration for a population of cells using single-cell RNA-seq data (scRNA-seq), and possibly other data modalities. Methods are also provided to assign cells to inferred clones and explore differences in gene expression between clones. These methods can flexibly integrate information from imperfect clonal trees inferred based on bulk exome-seq data, and sparse variant alleles expressed in scRNA-seq data. A flexible beta-binomial error model that accounts for stoc
when_to_use: Use when: Clone ID with cardelino; Single-cell RNA-seq analysis (cardelino). Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# cardelino

## Workflows

### Standard Workflow

Assign cells to clones using scRNA-seq variant counts and a pre-defined clonal tree configuration.

```r
library(cardelino)
library(ggplot2)

# 1. Load scRNA-seq variant data
vcf_file <- system.file("extdata", "cellSNP.cells.vcf.gz", package = "cardelino")
input_data <- load_cellSNP_vcf(vcf_file)

# 2. Load clonal tree configuration and align variant IDs
canopy_res <- readRDS(system.file("extdata", "canopy_results.coveraged.rds", package = "cardelino"))
Config <- canopy_res$tree$Z
rownames(Config) <- gsub(":", "_", rownames(Config))

# 3. Run Bayesian clustering using clone_id with the configuration matrix
set.seed(7)
assignments <- clone_id(input_data$A, input_data$D, Config = Config, min_iter = 800, max_iter = 1200)

# 4. Assign cells to clones
df <- assign_cells_to_clones(assignments$prob)

# 5. Visualize results
prob_heatmap(assignments$prob)
heat_matrix(t(assignments$Config_prob - Config))

AF <- as.matrix(input_data$A / input_data$D)
cardelino::vc_heatmap(AF, assignments$prob, Config, show_legend=TRUE)
```
*Note: Inputs are variant-by-cell matrices of alternative allele counts (A) and total coverage (D), plus a prior configuration matrix (Config); output is a list containing posterior assignment probabilities and updated clonal configurations.*

### Clone Id Denovo

Infer clonal structure and assign cells to clones de-novo without a pre-defined clonal tree, typically using mitochondrial or high-coverage variants.

```r
library(cardelino)

# 1. Read AD and DP matrices and assign variant and cell names
AD_file <- system.file("extdata", "passed_ad.mtx", package = "cardelino")
DP_file <- system.file("extdata", "passed_dp.mtx", package = "cardelino")
id_file <- system.file("extdata", "passed_variant_names.txt", package = "cardelino")

AD <- Matrix::readMM(AD_file)
DP <- Matrix::readMM(DP_file)
var_ids <- read.table(id_file)
rownames(AD) <- rownames(DP) <- var_ids[, 1]
colnames(AD) <- colnames(DP) <- paste0('Cell', seq(ncol(DP)))

# 2. Run de-novo Bayesian clustering using clone_id with Config=NULL
set.seed(7)
assign_mtClones <- clone_id(AD, DP, Config=NULL, n_clone = 3, keep_base_clone=FALSE)

# 3. Threshold the posterior configuration probability matrix
Config_mt <- assign_mtClones$Config_prob
Config_mt[Config_mt >= 0.5] = 1
Config_mt[Config_mt < 0.5] = 0

# 4. Visualize cell assignments and clonal configurations
AF_mt <- as.matrix(AD / DP)
cardelino::vc_heatmap(AF_mt, assign_mtClones$prob, Config_mt, show_legend=TRUE)
```
*Note: Inputs are sparse matrices of alternative (AD) and total (DP) counts without a prior tree; output is a de-novo clonal assignment and inferred configuration matrix.*

## When to Use
- To assign single-cell transcriptomes to individual clones using sparse variant information from scRNA-seq reads.
- To integrate prior clonal tree configurations (e.g., from bulk DNA-seq using Canopy) with single-cell RNA-seq variant counts.
- To perform de-novo clonal clustering on mitochondrial variations (e.g., from MQuad) without a prior clonal tree.

## When NOT to Use
- Do not use if you do not have variant-level coverage and alternative allele count matrices (A and D) extracted from single-cell sequencing reads.
- Do not use for bulk-only clonal tree reconstruction; use tools like `Canopy` instead.

## Data Requirements
- Matrix `A` (or `AD`): variant x cell matrix of integer counts supporting the alternative allele.
- Matrix `D` (or `DP`): variant x cell matrix of integer counts providing the total read coverage at each site.
- `Config`: variant x clone binary configuration matrix (optional for de-novo mode).

## Key Parameters
- **Config** (NULL): Prior variant-by-clone configuration matrix. Set to `NULL` for de-novo mode.
- **n_clone** (3): Number of clones to infer when `Config` is `NULL`.
- **min_iter** (800): Minimum number of Gibbs sampling iterations.
- **max_iter** (1200): Maximum number of Gibbs sampling iterations.
- **keep_base_clone** (FALSE): Logical indicating whether to keep the first clone as a base clone with no mutations.

## Best Practices
- Ensure variant IDs are perfectly matched between the scRNA-seq matrices (`A` and `D`) and the prior configuration matrix (`Config`).
- Use the Geweke z-statistic (checked automatically in `clone_id`) to ensure Gibbs sampling convergence.
- For de-novo mode, run `clone_id` multiple times with different random seeds and select the run with the highest DIC to avoid local optima.

## Common Pitfalls
- Gibbs sampler not converging: Increase `min_iter` and `max_iter` parameters.
- Local optima in de-novo mode: Run multiple initializations with different seeds.

## Alternatives
- `Canopy` for bulk DNA-seq clonal tree inference.
- `MQuad` for mitochondrial variant calling.

## Citations
- McCarthy, D., & Huang, Y. (2026). cardelino: Clonal tree configuration and cell assignment from single-cell data.

## References
- Homepage: bioconductor.org/packages/cardelino
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cardelino/inst/doc/vignette-cloneid.html
