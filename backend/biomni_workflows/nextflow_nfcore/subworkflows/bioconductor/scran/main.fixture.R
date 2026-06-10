# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scran", "scRNAseq", "scrapper", "scuttle", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scran)
library(scRNAseq)

# Fetch the dataset as used in the vignette
sce <- GrunPancreasData()

# The vignette uses the 'scrapper' package to prepare the object.
# If it is available in the environment, we use it; otherwise, we manually
# reproduce the required components (normalization, variance modeling, PCA) 
# that the downstream vignette steps expect.
if (requireNamespace("scrapper", quietly = TRUE)) {
    library(scrapper)
    results <- analyze.se(sce, num.threads = 2)
    sce.ready <- results$x
} else {
    library(scuttle)
    library(scater)
    
    # Basic filtering to ensure downstream steps work
    sce <- sce[rowSums(counts(sce)) > 0, ]
    
    # Quick clustering and normalization
    clusters <- quickCluster(sce)
    sce <- computeSumFactors(sce, clusters = clusters)
    sce.ready <- logNormCounts(sce)
    
    # Variance modeling
    dec <- modelGeneVar(sce.ready)
    rowData(sce.ready)$fitted <- dec$fitted
    rowData(sce.ready)$variances <- dec$total
    rowData(sce.ready)$residuals <- dec$bio
    
    # Identify Highly Variable Genes (HVGs)
    hvg_idx <- getTopHVGs(dec, n = 1000)
    rowData(sce.ready)$hvg <- rownames(sce.ready) %in% hvg_idx
    
    # Dimensionality reduction (PCA)
    sce.ready <- runPCA(sce.ready, subset_row = hvg_idx)
    
    # Compute actual variance explained by each PC for denoisePCANumber()
    pca_matrix <- reducedDim(sce.ready, "PCA")
    actual_vars <- apply(pca_matrix, 2, var)
    metadata(sce.ready)$PCA <- list(variance.explained = actual_vars)
}

# Serialize the prepared object to the expected input file
saveRDS(sce.ready, "sce.ready")