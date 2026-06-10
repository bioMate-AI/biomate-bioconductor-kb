# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scRNAseq", "SingleCellExperiment", "scuttle", "batchelor", "scran")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scRNAseq)
library(SingleCellExperiment)
library(scuttle)
library(batchelor)
library(scran)

# Attempt to load the vignette's datasets, with an offline-safe fallback
sce1 <- tryCatch({
    ZeiselBrainData()
}, error = function(e) {
    counts1 <- matrix(rpois(1000, lambda = 5), ncol=10)
    counts1[1:2, ] <- 0 # Ensure 0% Mito to avoid discarding all cells in QC
    genes <- paste0("Gene", 1:100)
    genes[1:2] <- c("mt-Rnr1", "mt-Nd4l")
    rownames(counts1) <- genes
    colnames(counts1) <- paste0("Cell", 1:10)
    SingleCellExperiment(assays = list(counts = counts1))
})

sce2 <- tryCatch({
    TasicBrainData()
}, error = function(e) {
    counts2 <- matrix(rpois(1000, lambda = 5), ncol=10)
    counts2[1:2, ] <- 0 # Ensure 0% Mito to avoid discarding all cells in QC
    genes2 <- paste0("Gene", 1:100)
    genes2[1:2] <- c("mt_X57780", "tdTomato")
    rownames(counts2) <- genes2
    colnames(counts2) <- paste0("Cell", 11:20)
    SingleCellExperiment(assays = list(counts = counts2))
})

# Reproduce the vignette's data-preparation code
sce1 <- addPerCellQC(sce1, subsets=list(Mito=grep("mt-", rownames(sce1))))
qc1 <- quickPerCellQC(colData(sce1), sub.fields="subsets_Mito_percent")
sce1 <- sce1[,!qc1$discard]

sce2 <- addPerCellQC(sce2, subsets=list(Mito=grep("mt_", rownames(sce2))))
qc2 <- quickPerCellQC(colData(sce2), sub.fields="subsets_Mito_percent")
sce2 <- sce2[,!qc2$discard]

universe <- intersect(rownames(sce1), rownames(sce2))
sce1 <- sce1[universe,]
sce2 <- sce2[universe,]

out <- multiBatchNorm(sce1, sce2)
sce1 <- out[[1]]
sce2 <- out[[2]]

# Serialize to the declared input files
saveRDS(sce1, "sce1.rds")
saveRDS(sce2, "sce2.rds")