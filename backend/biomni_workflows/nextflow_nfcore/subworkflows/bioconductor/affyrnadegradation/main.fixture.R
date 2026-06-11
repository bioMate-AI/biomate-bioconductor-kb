# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AffyRNADegradation", "AmpAffyExample")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AffyRNADegradation)
library(AmpAffyExample)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code for AmpData
# This comes from vignette chunk number 1
data(AmpData)

# 2. Serialize AmpData to "AmpData.rds"
saveRDS(AmpData, file = "AmpData.rds")

# 3. Handle probeDists:
# The vignette describes the structure of 'probeDists' but does not provide
# executable R code to generate it from 'AmpData' or any other data() call.
# It states that these files are "pre-computed" or "custom created" and
# provides an example table structure.