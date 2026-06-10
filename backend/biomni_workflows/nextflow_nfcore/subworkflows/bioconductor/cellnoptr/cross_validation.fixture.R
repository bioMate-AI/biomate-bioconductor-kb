# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CellNOptR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CellNOptR)

# Reproduce the CNOlist object from the vignette
# The workflow expects this to be named "CNOlist_ToyPB"
data(CNOlistToy, package="CellNOptR")
cnolist_obj <- CNOlist(CNOlistToy)

# Serialize the CNOlist object to the file "CNOlist_ToyPB"
# The workflow's read_input_object function attempts to read this directly as an RDS file.
saveRDS(cnolist_obj, "CNOlist_ToyPB")

# Reproduce the PKN model object from the vignette
# The workflow expects this to be named "PKN_ToyPB"
data(ToyModel, package="CellNOptR")
pknmodel_obj <- ToyModel

# Serialize the PKN model object to the file "PKN_ToyPB"
# The workflow's read_input_object function attempts to read this directly as an RDS file.
saveRDS(pknmodel_obj, "PKN_ToyPB")