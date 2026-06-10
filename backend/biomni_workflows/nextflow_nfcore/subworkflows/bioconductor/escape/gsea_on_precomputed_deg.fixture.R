# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("escape", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(escape)
library(Seurat)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# For 'escape.gene.sets':
# The vignette explicitly loads this built-in dataset.
data("escape.gene.sets", package = "escape")

# For 'DEG.markers':
# The vignette does not provide code to generate 'deg_results.csv'.
# We create a plausible mock object based on common DEG results,
# using gene names from the 'pbmc_small' dataset for realism,
# as 'pbmc_small' is used extensively in the vignette.
pbmc_small <- get("pbmc_small")
genes <- rownames(pbmc_small)

# Create a mock DEG.markers data frame with gene names as row names
# and typical differential expression statistics.
set.seed(123) # For reproducibility of random values
num_genes_in_deg <- 100 # A reasonable number of genes for a DEG list
selected_genes <- sample(genes, num_genes_in_deg, replace = FALSE)

DEG.markers <- data.frame(
  row.names = selected_genes,
  avg_log2FC = rnorm(num_genes_in_deg, mean = 0.5, sd = 1.5),
  p_val = runif(num_genes_in_deg, min = 0, max = 1),
  p_val_adj = runif(num_genes_in_deg, min = 0, max = 1)
)

# Adjust some values to simulate significant genes and proper p-value relationships
DEG.markers$p_val_adj <- pmin(DEG.markers$p_val * sample(c(1, 1.5, 2), num_genes_in_deg, replace = TRUE), 1)
# Ensure some genes are clearly significant
DEG.markers$p_val[1:10] <- c(0.0001, 0.0005, 0.001, 0.005, 0.01, 0.02, 0.03, 0.04, 0.045, 0.049)
DEG.markers$p_val_adj[1:10] <- p.adjust(DEG.markers$p_val[1:10], method = "BH")
DEG.markers$avg_log2FC[1:10] <- c(3.5, -2.8, 4.1, -3.2, 2.9, 2.1, -1.9, 1.5, -1.2, 1.0)


# 2. Serialize objects to EACH declared input file

# Save DEG.markers to "deg_results.csv"
# 'row.names = TRUE' ensures the first column contains gene names,
# matching the workflow's 'read.csv("deg_results.csv", row.names = 1)'
write.csv(DEG.markers, "deg_results.csv", row.names = TRUE)

# Save escape.gene.sets to "gene_sets.rds"
saveRDS(escape.gene.sets, "gene_sets.rds")