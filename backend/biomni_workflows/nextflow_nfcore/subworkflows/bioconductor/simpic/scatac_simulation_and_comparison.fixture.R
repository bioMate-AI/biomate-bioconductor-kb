# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("simPIC", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(simPIC)
    library(Matrix)
})

test_rds_path <- system.file("extdata", "test.rds", package = "simPIC")

if (file.exists(test_rds_path)) {
    counts <- readRDS(test_rds_path)
} else {
    # Fallback: create a synthetic dgCMatrix matching the expected format
    set.seed(567)
    mat <- matrix(rpois(1000 * 100, lambda = 0.05), nrow = 1000, ncol = 100)
    rownames(mat) <- paste0("chr1-", seq(1000, 1000 * 1000, by = 1000), "-", seq(1500, 1000 * 1000 + 500, by = 1000))
    colnames(mat) <- paste0("CELL", 1:100, "-1")
    counts <- as(mat, "dgCMatrix")
}

saveRDS(counts, "test.rds")