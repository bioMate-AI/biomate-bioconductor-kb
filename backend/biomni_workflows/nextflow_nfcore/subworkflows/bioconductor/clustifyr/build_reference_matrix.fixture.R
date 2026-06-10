# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clustifyr", "SingleCellExperiment", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clustifyr)
library(SingleCellExperiment)
library(Seurat) # SeuratObject is loaded via namespace in vignette, Seurat provides CreateSeuratObject

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette explicitly creates pbmc_matrix and pbmc_meta from clustifyr's internal datasets.
pbmc_matrix <- clustifyr::pbmc_matrix_small
pbmc_meta   <- clustifyr::pbmc_meta

# The workflow reads 'sce.rds' and 'so.rds', but the vignette does not explicitly
# show code to create 'sce' (SingleCellExperiment) or 'so' (Seurat) objects from
# pbmc_matrix and