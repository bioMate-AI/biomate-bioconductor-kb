# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CellNOptR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CellNOptR)

# Reproduce the vignette's data-preparation code
data("ToyModel", package="CellNOptR")
data("CNOlistToy", package="CellNOptR")

# The workflow expects a CNOlist object for CNOlistToy2
# The vignette shows CNOlist(CNOlistToy) creates this object
CNOlistToy_obj <- CNOlist(CNOlistToy)

# Serialize the objects to the declared input files
saveRDS(ToyModel, "ToyModel2.rds")
saveRDS(CNOlistToy_obj, "CNOlistToy2.rds")