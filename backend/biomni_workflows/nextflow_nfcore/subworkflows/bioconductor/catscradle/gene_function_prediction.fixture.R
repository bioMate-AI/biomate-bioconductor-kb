# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CatsCradle", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CatsCradle)
library(Seurat)

# Initialize the example data generator as shown in the vignette
getExample <- make.getExample()

# 1. Generate and save the transposed Seurat object
exSeuratObj <- getExample('exSeuratObj')
STranspose <- transposeObject(exSeuratObj)
saveRDS(STranspose, "transposed_gene_seurat.rds")

# 2. Generate and save the gene sets (e.g., Hallmark)
hallmark <- getExample('hallmark')
saveRDS(hallmark, "gene_sets.rds")