# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("betaHMM")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(betaHMM)

# Load the datasets provided by the package
data("pca_methylation_data", package = "betaHMM")
data("annotation_data", package = "betaHMM")

# Serialize the objects to the exact filenames expected by the workflow
# Since the read excerpt is empty, we save as RDS to preserve the exact data frame structure
saveRDS(pca_methylation_data[, 1:5], "pca_methylation_data[, 1:5]")
saveRDS(pca_methylation_data[, 1:5], "pca_methylation_data[,1:5]") # Fallback for spacing differences
saveRDS(annotation_data, "annotation_data")