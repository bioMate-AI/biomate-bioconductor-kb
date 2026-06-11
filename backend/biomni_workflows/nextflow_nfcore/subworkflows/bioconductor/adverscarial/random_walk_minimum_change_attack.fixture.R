# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("adverSCarial", "LoomExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(adverSCarial)
library(LoomExperiment)

# Reproduce the data-preparation code from the vignette
pbmcPath <- system.file("extdata", "pbmc_short.loom", package="adverSCarial")
lfile <- import(pbmcPath, type="SingleCellLoomExperiment")

# The workflow reads 'sce_object.ext' and assigns it to 'test_4k'.
# Based on the vignette, the 'lfile' object (a SingleCellLoomExperiment)
# is the primary data structure from which counts and cell types are extracted.
# Therefore, we save 'lfile' as 'sce_object.ext'.
saveRDS(lfile, file="sce_object.ext")