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

# Reproduce the VIGNETTE'S OWN data-preparation code
pbmcPath <- system.file("extdata", "pbmc_short.loom", package="adverSCarial")
lfile <- import(pbmcPath, type="SingleCellLoomExperiment")
matPbmc <- counts(lfile)
cellTypes <- rowData(lfile)$cell_type

# Serialize the objects to the declared input files.
# The workflow's read functions attempt readRDS first (despite a buggy conditional).
# Using saveRDS is the most robust way to serialize R objects, especially S4 objects
# like 'matPbmc' (a DelayedMatrix), as explicitly allowed by the prompt.
saveRDS(matPbmc, "counts_matrix.ext")
saveRDS(cellTypes, "cell_annotations.ext")