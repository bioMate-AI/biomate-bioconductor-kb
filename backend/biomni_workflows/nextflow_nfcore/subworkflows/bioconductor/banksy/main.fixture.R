# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Banksy", "data.table", "SummarizedExperiment", "SpatialExperiment", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Banksy)
library(data.table)
library(SummarizedExperiment)
library(SpatialExperiment)
library(scater) # For plotColData, not strictly needed for data prep but good practice to include vignette libs

# Define output file paths as per the workflow description
gcm_path <- "gcm_fixture.csv.gz"
mdata_path <- "mdata_fixture.csv.gz"

# --- Reproduce the VIGNETTE'S OWN data-preparation code ---
# The vignette for "Domain segmentation (STARmap PLUS mouse brain)"
# describes reading gcm_path and mdata_path, but does not provide
# the source code to generate these files directly.
# However, the Banksy