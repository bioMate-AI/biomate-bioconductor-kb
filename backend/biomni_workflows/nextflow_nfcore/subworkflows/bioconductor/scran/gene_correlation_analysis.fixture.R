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

# The vignette uses GrunPancreasData from scRNAseq
sce <- GrunPancreasData()

# The vignette uses the 'scrapper' package to prepare the object.
# We provide a fallback using standard scran/scater functions to populate 
# the exact fields required by the vignette if 'scrapper' is unavailable.
if (requireNamespace("scrapper", quietly = TRUE)) {
    library(scrapper)
    results <- analyze.se(sce, num.threads = 2)
    sce.ready <- results$x
} else {
    library(scuttle)
    library(scater)
    
    # Subsample to speed up test fixture generation
    sce <- sce[1:1000, 1:300]
    
    # Normalize counts
    sce <- logNormCounts(sce)
    
    # Variance modeling
    dec <- modelGeneVar(sce)
    rowData(sce)$variances <- dec$total
    rowData(sce)$fitted <- dec$tech
    rowData(sce)$residuals <- dec$bio
    rowData(sce)$hvg <- dec$bio > 0
    
    # PCA
    set.seed(100)
    sce <- runPCA(sce, subset_row = which(rowData(sce)$hvg))
    
    # The vignette expects metadata(sce.ready)$PCA$variance.explained
    metadata(sce)$PCA <- list(variance.explained = attr(reducedDim(sce, "PCA"), "percentVar"))
    
    sce.ready <- sce
}

# Serialize the object to the expected input file
saveRDS(sce.ready, "sce.ready")