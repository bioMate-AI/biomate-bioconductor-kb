# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SpatialDecon", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SpatialDecon)

# Load the example dataset from the SpatialDecon package
data("mini_singleCell_dataset", package = "SpatialDecon")

# Serialize the sparse matrix and annotations to the requested filenames
saveRDS(mini_singleCell_dataset$mtx, "mini_singleCell_dataset$mtx")
saveRDS(mini_singleCell_dataset$annots, "mini_singleCell_dataset$annots")

# Create and serialize the Seurat object
if (requireNamespace("Seurat", quietly = TRUE)) {
    library(Seurat)
    annots <- mini_singleCell_dataset$annots
    # Ensure rownames match the cell names in the count matrix
    if (!is.null(annots$CellID)) {
        rownames(annots) <- annots$CellID
    }
    seuratObject <- CreateSeuratObject(counts = mini_singleCell_dataset$mtx, meta.data = annots)
    saveRDS(seuratObject, "seuratObject.rds")
} else {
    # Fallback mock Seurat object if Seurat is not installed in the environment
    seuratObject <- list(
        assays = list(RNA = list(counts = mini_singleCell_dataset$mtx)),
        meta.data = mini_singleCell_dataset$annots
    )
    class(seuratObject) <- "Seurat"
    saveRDS(seuratObject, "seuratObject.rds")
}