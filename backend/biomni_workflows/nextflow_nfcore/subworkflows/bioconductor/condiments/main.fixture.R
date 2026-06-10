# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("condiments", "dplyr", "tidyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(condiments)
library(dplyr)
library(tidyr)

set.seed(2071)
data("toy_dataset", package = "condiments")
df <- toy_dataset$sd

# Create and save reduced_dim_matrix
# This corresponds to `rd <- as.matrix(df[, c("Dim1", "Dim2")])` in the vignette.
reduced_dim_matrix <- as.matrix(df[, c("Dim1", "Dim2")])
saveRDS(reduced_dim_matrix, "reduced_dim_matrix")

# Create and save condition_labels
# This corresponds to `conditions = df$conditions` in the vignette.
condition_labels <- df$conditions
saveRDS(condition_labels, "condition_labels")

# Create and save cluster_labels
# The vignette uses `df$cl` for cluster labels in `slingshot(rd, df$cl)`.
# Given the available data in `toy_dataset$sd` and the visualization,
# `df$cl` is interpreted as `df$lineages`.
cluster_labels <- df$lineages
saveRDS(cluster_labels, "cluster_labels")