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

# Extract the objects from the loaded list
dataMatrix_orig <- diaplasma$dataMatrix
sampleMetadata <- diaplasma$sampleMetadata
variableMetadata <- diaplasma$variableMetadata

# Apply the feature selection as described in the vignette
featureSelVl <- variableMetadata[, "mzmed"] >= 450 & variableMetadata[, "mzmed"] < 500
dataMatrix <- dataMatrix_orig[, featureSelVl]

# Serialize the dataMatrix and sampleMetadata objects to .rds files
# The workflow's read_input function prioritizes .rds files.
saveRDS(dataMatrix, "dataMatrix.rds")
saveRDS(sampleMetadata, "sampleMetadata.rds")