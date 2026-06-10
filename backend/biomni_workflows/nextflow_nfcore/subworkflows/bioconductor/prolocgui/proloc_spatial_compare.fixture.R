# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("pRolocGUI", "pRolocdata", "MSnbase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("pRolocGUI")
library("pRolocdata")
library("MSnbase")

# Load the example dataset from the companion data package as shown in the vignette
data("hyperLOPIT2015", package = "pRolocdata")

# Extract the expression (intensity) data and sample metadata (coldata)
intensity_data <- exprs(hyperLOPIT2015)
coldata_data <- pData(hyperLOPIT2015)

# Serialize to the required input files
write.csv(intensity_data, file = "intensity.csv", row.names = TRUE)
write.csv(coldata_data, file = "coldata.csv", row.names = TRUE)