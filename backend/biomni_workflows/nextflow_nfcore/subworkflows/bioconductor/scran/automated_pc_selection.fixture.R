# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scran", "scRNAseq", "scrapper", "scuttle")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scran)
library(scRNAseq)

# Load the dataset exactly as in the vignette
sce <- GrunPancreasData()

# The vignette uses the 'scrapper' package to prepare the data.
# We use it if available, otherwise we manually reconstruct the exact 
# SingleCellExperiment structure (PCA, variance statistics) required by the workflow.
if (requireNamespace("scrapper", quietly = TRUE)) {
    library(scrapper)
    results <- analyze.se(sce, num.threads = 2)
    sce.ready <- results$x
} else {
    library(scuttle)
    
    # Basic normalization
    sce <- logNormCounts(sce)
    
    # Variance modelling to populate rowData with required statistics
    dec <- modelGeneVar(sce, block = sce$donor)
    rowData(sce)$variances <- dec$total
    rowData(sce)$fitted <- dec$tech
    rowData(sce)$hvg <- dec$FDR < 0.05
    rowData(sce)$residuals <- dec$total - dec$tech
    
    # Ensure we have enough HVGs for downstream steps
    if (sum(rowData(sce)$hvg, na.rm = TRUE) < 2) {
        rowData(sce)$hvg[order(dec$FDR)[1:200]] <- TRUE
    }
    
    # PCA generation to populate reducedDims and metadata
    if (requireNamespace("scater", quietly = TRUE)) {
        sce <- scater::runPCA(sce, subset_row = which(rowData(sce)$hvg))
        metadata(sce)$PCA <- list(variance.explained = attr(reducedDim(sce, "PCA"), "percentVar"))
    } else {
        mat <- as.matrix(logcounts(sce)[which(rowData(sce)$hvg), ])
        pca <- prcomp(t(mat), rank. = min(50, ncol(mat), nrow(mat)))
        reducedDim(sce, "PCA") <- pca$x
        metadata(sce)$PCA <- list(variance.explained = (pca$sdev^2 / sum(pca$sdev^2)) * 100)
    }
    
    sce.ready <- sce
}

# Serialize the prepared object to the expected input file
saveRDS(sce.ready, "sce.ready")