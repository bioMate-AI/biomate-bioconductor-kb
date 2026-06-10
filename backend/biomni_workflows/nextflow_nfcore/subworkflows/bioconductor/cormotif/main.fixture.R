# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Cormotif")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Cormotif)

# Reproduce data preparation from the vignette
data(simudata2)
exprs.simu2 <- as.matrix(simudata2[, 2:25])
data(simu2_groupid)
data(simu2_compgroup)

# Serialize objects to the specified input files.
# The workflow's `read_file` function attempts `readRDS` first,
# making `saveRDS` the most robust serialization method.
saveRDS(exprs.simu2, "exprs.simu2")
saveRDS(simu2_groupid, "simu2_groupid")
saveRDS(simu2_compgroup, "simu2_compgroup")