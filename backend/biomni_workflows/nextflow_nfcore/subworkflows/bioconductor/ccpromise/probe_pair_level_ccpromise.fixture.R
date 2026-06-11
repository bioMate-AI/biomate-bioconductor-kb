# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CCPROMISE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CCPROMISE)

# Load the example datasets as shown in the vignette
data(exmplESet)
data(exmplMSet)
data(exmplGeneSet)
data(exmplPat)

# Serialize the objects to files using saveRDS, matching the workflow's read_input
saveRDS(exmplGeneSet, "exmplGeneSet")
saveRDS(exmplESet, "exmplESet")
saveRDS(exmplMSet, "exmplMSet")
saveRDS(exmplPat, "exmplPat")