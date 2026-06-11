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

# Reproduce testData from the vignette
data('testData')

# Serialize testData to testData.rds
saveRDS(testData, "testData.rds")

# Reproduce testDataSNE from the vignette
# The workflow reads testDataSNE_input, which corresponds to the 2D embedding (testDataSNE$Y)
testDataSNE <- Rtsne(testData[,2:15], pca=FALSE)

# Serialize the relevant part of testDataSNE (the Y matrix) to testDataSNE.rds
saveRDS(testDataSNE$Y, "testDataSNE.rds")