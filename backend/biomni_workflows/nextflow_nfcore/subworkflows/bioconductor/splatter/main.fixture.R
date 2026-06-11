# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("splatter", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(splatter)
library(scater)

# Set seed for reproducibility as in the vignette
set.seed(1)

# Create the SingleCellExperiment object 'sce' using mockSCE()
sce <- mockSCE()

# Extract the counts matrix from the 'sce' object
counts_mat <- counts(sce)

# Save the 'sce' object to "sce.rds"
saveRDS(sce, "sce.rds")

# Save the 'counts_mat' object to "counts.rds"
saveRDS(counts_mat, "counts.rds")