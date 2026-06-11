# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("epiregulon", "scMultiome", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(epiregulon)
    library(scMultiome)
    library(SingleCellExperiment)
})

# load the MAE object
mae <- scMultiome::reprogramSeq()

# extract peak matrix
PeakMatrix <- mae[["PeakMatrix"]]

# extract expression matrix
GeneExpressionMatrix <- mae[["GeneExpressionMatrix"]]
rownames(GeneExpressionMatrix) <- rowData(GeneExpressionMatrix)$name

# define the order of hash_assigment
GeneExpressionMatrix$hash_assignment <- factor(
    as.character(GeneExpressionMatrix$hash_assignment), 
    levels = c("HTO10_GATA6_UTR", "HTO2_GATA6_v2", "HTO8_NKX2.1_UTR", "HTO3_NKX2.1_v2", 
               "HTO1_FOXA2_v2", "HTO4_mFOXA1_v2", "HTO6_hFOXA1_UTR", "HTO5_NeonG_v2")
)

# extract dimensional reduction matrix
reducedDimMatrix <- reducedDim(mae[['TileMatrix500']], "LSI_ATAC")

# transfer UMAP_combined from TileMatrix to GeneExpressionMatrix
reducedDim(GeneExpressionMatrix, "UMAP_Combined") <- reducedDim(mae[['TileMatrix500']], "UMAP_Combined")

# Serialize to the declared input files
saveRDS(PeakMatrix, "PeakMatrix.rds")
saveRDS(GeneExpressionMatrix, "GeneExpressionMatrix.rds")
saveRDS(reducedDimMatrix, "reducedDimMatrix.rds")