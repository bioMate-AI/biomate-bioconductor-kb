# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("adSplit", "golubEsets", "hu6800.db")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(adSplit)
library(golubEsets)
library(hu6800.db)

# Prepare Matrix
data(Golub_Merge)
e <- exprs(Golub_Merge)
saveRDS(e, "Matrix.rds")

# Prepare Environment
EID2PSenv <- makeEID2PROBESenv(hu6800ENTREZID)
saveRDS(EID2PSenv, "Environment.rds")