# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TENxPBMCData", "scater", "SingleCellExperiment", "mbkmeans", "DelayedMatrixStats")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TENxPBMCData)
library(scater)
library(SingleCellExperiment)
library(mbkmeans)
library(DelayedMatrixStats)

# Reproduce the example dataset from the vignette
tenx_pbmc4k <- TENxPBMCData(dataset = "pbmc4k")
set.seed(1034)
idx <- sample(seq_len(NCOL(tenx_pbmc4k)), 100)
sce <- tenx_pbmc4k[, idx]

# Normalization
sce <- logNormCounts(sce)
vars <- rowVars(logcounts(sce))
names(vars) <- rownames(sce)
vars <- sort(vars, decreasing = TRUE)
sce1000 <- sce[names(vars)[1:1000],]

# Perform PCA as done later in the vignette for 'mat'
# This step is crucial because the workflow reads 'pca_matrix.rds'
# which is derived from reducedDim(sce1000, "PCA")
sce1000 <- runPCA(sce1000, ncomponents=20)

# Extract the PCA matrix for pca_matrix.rds
mat <- reducedDim(sce1000, "PCA")

# Save the objects to .rds files as expected by the workflow
saveRDS(mat, "pca_matrix.rds")
saveRDS(sce1000, "sce_object.rds")