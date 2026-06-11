# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DeMixT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DeMixT)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette uses `data("test.data.2comp")` for its examples.
data("test.data.2comp")

# The workflow reads input files named PRAD, Normal.id, Tumor.id.
# Based on the DeMixT function signatures and common deconvolution workflows:
# - PRAD is likely the mixed expression data (data.Y).
# - Normal.id is likely the identifiers for the normal reference samples.
# - Tumor.id is likely the identifiers for the mixed tumor samples (which are the samples in data.Y).

# Extract the mixed expression data
PRAD_data <- test.data.2