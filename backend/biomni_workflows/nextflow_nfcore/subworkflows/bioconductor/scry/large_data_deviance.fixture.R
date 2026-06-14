# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment", "HDF5Array")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleCellExperiment)
library(HDF5Array)
library(DelayedArray)

set.seed(101)
# Create a synthetic counts matrix
counts_mat <- matrix(rpois(20000, lambda = 0.5), nrow=200, ncol=100)
rownames(counts_mat) <- paste0("Gene", 1:200)
colnames(counts_mat) <- paste0("Cell", 1:100)

# Wrap as a DelayedArray. NOTE: an HDF5Array serialized with saveRDS only stores a *pointer*
# to its backing .h5 file, which the harness does not stage alongside the .rds — so readRDS in
# the workflow would dereference a missing file. Use an in-memory DelayedArray seed instead so
# the .rds is fully self-contained while still exercising scry's DelayedArray/devianceFeature
# code path.
h5counts <- DelayedArray(counts_mat)

# Save h5counts object (portable, no external .h5 dependency)
saveRDS(h5counts, "h5counts.rds")

# Create SingleCellExperiment with the DelayedArray-backed counts
sce <- SingleCellExperiment(assays = list(counts = h5counts))
colData(sce)$phenoid <- sample(c("B-cells", "monocytes", "T-cells"), 100, replace=TRUE)

# Save sce object
saveRDS(sce, "sce.rds")