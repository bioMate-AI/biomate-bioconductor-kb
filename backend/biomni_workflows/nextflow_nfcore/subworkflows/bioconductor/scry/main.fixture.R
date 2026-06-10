# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment", "DuoClustering2018")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(SingleCellExperiment))
suppressPackageStartupMessages(library(DuoClustering2018))

sce <- tryCatch({
    sce_full_Zhengmix4eq()
}, error = function(e) {
    counts_mat <- matrix(rep(c(0, 1, 2, 5, 10), 20000), nrow = 1000, ncol = 100)
    rownames(counts_mat) <- paste0("Gene", 1:1000)
    colnames(counts_mat) <- paste0("Cell", 1:100)
    sce_obj <- SingleCellExperiment(assays = list(counts = counts_mat))
    colData(sce_obj)$phenoid <- rep(c("B-cells", "monocytes", "T-cells", "naive cytotoxic"), 25)
    sce_obj
})

saveRDS(sce, "sce.rds")