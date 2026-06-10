# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment", "scMerge")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(SingleCellExperiment)
  library(scMerge)
})

# Reproduce the vignette's data-preparation code
data("example_sce", package = "scMerge")
data("segList_ensemblGeneID", package = "scMerge")

# Serialize the objects to the exact input files the workflow reads
saveRDS(example_sce, "example_sce.rds")
saveRDS(segList_ensemblGeneID, "segList_ensemblGeneID.rds")