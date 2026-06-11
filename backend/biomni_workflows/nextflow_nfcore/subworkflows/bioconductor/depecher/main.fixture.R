# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DepecheR", "Rtsne")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DepecheR)
library(Rtsne)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data('testData')
testDataSNE <- Rtsne(testData[,2:15], pca=FALSE)

# 2. Serialize objects to declared input files in the exact format
saveRDS(testData, "testData.rds")
saveRDS(testDataSNE, "testDataSNE.rds")