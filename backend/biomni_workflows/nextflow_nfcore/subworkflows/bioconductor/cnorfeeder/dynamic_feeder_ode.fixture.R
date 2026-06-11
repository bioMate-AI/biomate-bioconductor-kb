# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CellNOptR", "CNORfeeder")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CellNOptR)
library(CNORfeeder)

# Load the data objects as they appear in the vignette
data(CNOlistToy_Gene, package="CNORfeeder")
data(ToyModel_Gene, package="CNORfeeder")
data(database, package="CNORfeeder")

# Serialize the objects to the exact filenames and format the workflow expects
saveRDS(CNOlistToy_Gene, "CNOlistToy_Gene.rds")
saveRDS(ToyModel_Gene, "ToyModel_Gene.rds")
saveRDS(database, "database.rds")