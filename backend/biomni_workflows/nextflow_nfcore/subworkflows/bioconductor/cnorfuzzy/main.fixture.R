# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNORfuzzy", "CellNOptR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNORfuzzy)
library(CellNOptR) # Required for data(..., package="CellNOptR")

# Reproduce the vignette's data-preparation code
data(CNOlistDREAM, package="CellNOptR")
data(DreamModel, package="CellNOptR")

# Serialize the objects to the declared input files
saveRDS(CNOlistDREAM, file = "CNOlistDREAM")
saveRDS(DreamModel, file = "DreamModel")