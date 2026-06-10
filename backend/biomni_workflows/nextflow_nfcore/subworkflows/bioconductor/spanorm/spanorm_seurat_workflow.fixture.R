# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SpaNorm", "SpatialExperiment", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(SpaNorm)
    library(SpatialExperiment)
    library(Seurat)
})

# Load sample data from SpaNorm
data("HumanDLPFC", package = "SpaNorm")

# Change gene IDs to gene names as per vignette
rownames(HumanDLPFC) <- rowData(HumanDLPFC)$gene_name

# Filter genes expressed in 20% of spots
keep <- filterGenes(HumanDLPFC, 0.2)
HumanDLPFC <- HumanDLPFC[keep, ]

# Extract counts and spatial coordinates
counts_mat <- counts(HumanDLPFC)
coords <- as.data.frame(spatialCoords(HumanDLPFC))

# Create Seurat object
seurat_obj <- CreateSeuratObject(counts = counts_mat)

# Add spatial coordinates to metadata
seurat_obj <- AddMetaData(seurat_obj, metadata = coords)

# Serialize the Seurat object to RDS
saveRDS(seurat_obj, "input.rds")