# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scRNAseq", "scuttle", "batchelor")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(scRNAseq)
    library(scuttle)
    library(batchelor)
})

# Load demonstration data from the companion ExperimentData package
sce1 <- ZeiselBrainData()
sce2 <- TasicBrainData()

# Apply quality control as per the vignette
sce1 <- addPerCellQC(sce1, subsets=list(Mito=grep("mt-", rownames(sce1))))
qc1 <- quickPerCellQC(colData(sce1), sub.fields="subsets_Mito_percent")
sce1 <- sce1[,!qc1$discard]

sce2 <- addPerCellQC(sce2, subsets=list(Mito=grep("mt_", rownames(sce2))))
qc2 <- quickPerCellQC(colData(sce2), sub.fields="subsets_Mito_percent")
sce2 <- sce2[,!qc2$discard]

# Subset to the common universe of genes
universe <- intersect(rownames(sce1), rownames(sce2))
sce1 <- sce1[universe,]
sce2 <- sce2[universe,]

# Compute log-normalized expression values
out <- multiBatchNorm(sce1, sce2)
sce1 <- out[[1]]
sce2 <- out[[2]]

# Serialize the prepared SingleCellExperiment objects to the expected input files
saveRDS(sce1, "sce1")
saveRDS(sce2, "sce2")