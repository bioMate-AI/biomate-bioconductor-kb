# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("biosigner")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(biosigner)

# Load the diaplasma dataset
data(diaplasma)

# The vignette applies filtering to dataMatrix and variableMetadata.
# In the vignette, `attach(diaplasma)` is used, and then `dataMatrix` and
# `variableMetadata` are modified in the global environment.
# To create a self-contained fixture that represents the data *after*
# these preparation steps, we apply the filtering directly to the
# components within the `diaplasma` list.

# Apply the filtering logic from the vignette
featureSelVl <- diaplasma$variableMetadata[, "mzmed"] >= 450 & diaplasma$variableMetadata[, "mzmed"] < 500

# Update the dataMatrix and variable