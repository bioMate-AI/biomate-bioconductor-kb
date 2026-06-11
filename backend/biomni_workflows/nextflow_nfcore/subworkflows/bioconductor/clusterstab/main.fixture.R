# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clusterStab", "genefilter", "fibroEset", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clusterStab)
library(genefilter)
library(fibroEset)
library(Biobase) # Required for exprs() on ExpressionSet objects

# Reproduce the vignette's data-preparation code
data(fibroEset)
exprs(fibroEset) <- log2(exprs(fibroEset))

# Serialize the prepared 'fibroEset' object to the declared input file names
saveRDS(fibroEset, "fibroEset.rds")
saveRDS(fibroEset, "fibroEset.rds")