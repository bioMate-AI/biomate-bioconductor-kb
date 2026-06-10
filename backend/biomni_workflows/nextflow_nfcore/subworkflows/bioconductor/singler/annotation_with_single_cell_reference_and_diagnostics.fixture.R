# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleR", "scRNAseq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleR)
library(scRNAseq)

# Prepare the reference dataset
sceM <- MuraroPancreasData()
sceM <- sceM[, !is.na(sceM$label)]

# Normalize reference dataset
if (requireNamespace("scrapper", quietly = TRUE)) {
    sceM <- scrapper::normalizeRnaCounts.se(sceM)
} else if (requireNamespace("scuttle", quietly = TRUE)) {
    sceM <- scuttle::logNormCounts(sceM)
} else {
    assay(sceM, "logcounts") <- log2(counts(sceM) + 1)
}

# Prepare the test dataset
sceG <- GrunPancreasData()
sceG <- sceG[, colSums(counts(sceG)) > 0] # Remove libraries with no counts

# Normalize test dataset
if (requireNamespace("scrapper", quietly = TRUE)) {
    sceG <- scrapper::normalizeRnaCounts.se(sceG)
} else if (requireNamespace("scuttle", quietly = TRUE)) {
    sceG <- scuttle::logNormCounts(sceG)
} else {
    assay(sceG, "logcounts") <- log2(counts(sceG) + 1)
}

# Subset to the first 100 cells to speed up as described in the vignette
if (ncol(sceG) > 100) {
    sceG <- sceG[, 1:100]
}

# Serialize the objects to the required input files
saveRDS(sceG, "test_dataset.rds")
saveRDS(sceM, "reference_dataset.rds")