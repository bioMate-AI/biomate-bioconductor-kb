# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("schex", "Seurat", "SingleCellExperiment", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(schex)
library(Seurat)
library(SingleCellExperiment)
library(scater)

pbmc_small_obj <- pbmc_small
saveRDS(pbmc_small_obj, "pbmc_small.rds")

tenx_pbmc3k <- as.SingleCellExperiment(pbmc_small_obj)
set.seed(10)
tenx_pbmc3k <- runUMAP(tenx_pbmc3k, dimred = "PCA", spread = 1, min_dist = 0.4)
saveRDS(tenx_pbmc3k, "tenx_pbmc3k.rds")