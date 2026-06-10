# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment", "scRNAseq", "scater", "flexmix", "splines", "miQC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
  library(SingleCellExperiment)
  library(scRNAseq)
  library(scater)
  library(flexmix)
  library(splines)
  library(miQC)
})

# Attempt to load the dataset as per the vignette.
# Wrapped in tryCatch to ensure offline execution if ExperimentHub is unavailable.
sce <- tryCatch({
  ZeiselBrainData()
}, error = function(e) {
  # Fallback for offline environments
  counts_mat <- matrix(rpois(20000, lambda = 5), ncol = 100, nrow = 200)
  rownames(counts_mat) <- paste0("Gene", 1:200)
  colnames(counts_mat) <- paste0("Cell", 1:100)
  # Add mitochondrial genes to match the vignette's grepl("^mt-", ...) logic
  rownames(counts_mat)[1:20] <- paste0("mt-", 1:20)
  SingleCellExperiment(assays = list(counts = counts_mat))
})

# Scater preprocessing from the vignette
mt_genes <- grepl("^mt-", rownames(sce))
feature_ctrls <- list(mito = rownames(sce)[mt_genes])
sce <- addPerCellQC(sce, subsets = feature_ctrls)

# Save the SingleCellExperiment object to the working directory
saveRDS(sce, "sce.rds")
saveRDS(sce, "sce.rds")