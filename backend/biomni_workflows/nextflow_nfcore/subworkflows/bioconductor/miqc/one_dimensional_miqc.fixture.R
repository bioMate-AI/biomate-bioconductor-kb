# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment", "scater", "miQC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(SingleCellExperiment)
    library(scater)
    library(miQC)
})

# Generate synthetic count data to avoid offline ExperimentHub fetch failures
set.seed(123)
n_genes <- 500
n_cells <- 200

counts <- matrix(rpois(n_genes * n_cells, lambda = 5), nrow = n_genes, ncol = n_cells)
rownames(counts) <- paste0("Gene", 1:n_genes)
# Designate some genes as mitochondrial
rownames(counts)[1:20] <- paste0("mt-", 1:20)
colnames(counts) <- paste0("Cell", 1:n_cells)

# Simulate compromised cells (high mitochondrial expression, low overall detection)
counts[1:20, 1:40] <- matrix(rpois(20 * 40, lambda = 50), nrow = 20, ncol = 40)
counts[21:n_genes, 1:40] <- matrix(rpois((n_genes - 20) * 40, lambda = 1), nrow = n_genes - 20, ncol = 40)

sce <- SingleCellExperiment(assays = list(counts = counts))

# Apply scater preprocessing as shown in the vignette
mt_genes <- grepl("^mt-", rownames(sce))
feature_ctrls <- list(mito = rownames(sce)[mt_genes])
sce <- addPerCellQC(sce, subsets = feature_ctrls)

# Serialize the SingleCellExperiment object to the expected input file
saveRDS(sce, "sce.rds")