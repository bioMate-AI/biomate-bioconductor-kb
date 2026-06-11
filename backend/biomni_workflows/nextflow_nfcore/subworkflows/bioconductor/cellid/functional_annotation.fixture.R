# Load necessary libraries
# CelliD is the main package for the workflow.
# Seurat is a dependency of CelliD and provides the Seurat object structure
# and functions like CreateSeuratObject, NormalizeData, ScaleData, GetAssayData.
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CelliD", "Seurat")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CelliD)
library(Seurat)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load the primary example datasets as shown in the vignette.
# CRITICAL NOTE: The vignette explicitly uses readRDS(url(...)) for these datasets.
# To adhere to the instruction "COPY the vignette's exact data-preparation code ...
# and reuse it verbatim" and "NEVER invent a dataset name, NEVER use random data,
# NEVER guess", these online data sources are used as presented in the vignette.
# If an offline alternative were provided within the vignette's code (e.g.,
# via data() or system.file()), it would be prioritized.
BaronMatrix <- readRDS(url("https://storage.googleapis.com/cellid-cbl/BaronMatrix.rds"))
BaronMetaData <- readRDS(url("https://storage.googleapis.com/cellid-cbl/BaronMetaData.rds"))

# Load protein-coding gene list (this is an offline data load from the CelliD package)
data("HgProteinCodingGenes")

# Restrict the expression matrix to protein-coding genes
BaronMatrixProt <- BaronMatrix[rownames(BaronMatrix) %in% HgProteinCodingGenes,]

# Create a Seurat object from the processed counts and metadata
Baron <- CreateSeuratObject(counts = BaronMatrixProt, project = "Baron", min.cells = 5, meta.data = BaronMetaData)

# Perform library-size normalization and log-transformation
Baron <- NormalizeData(Baron)

# Perform centering and scaling of gene expression values
Baron <- ScaleData(Baron, features = rownames(Baron))

# Perform CelliD dimensionality reduction through Multiple Correspondence Analysis (MCA)
Baron <- RunMCA(Baron)

# 2. Serialize the objects to EACH declared input file

# expression_matrix.rds: The scaled expression matrix from the Seurat object.
# After NormalizeData and ScaleData, the scaled data is stored in the 'scale.data' slot.
expression_matrix <- Seurat::GetAssayData(Baron, assay = "RNA", slot = "scale.data")
saveRDS(expression_matrix, "expression_matrix.rds")

# metadata.rds: The cell metadata associated with the Seurat object.
metadata <- Baron@meta.data
saveRDS(metadata, "metadata.rds")

# pathway_genesets.rds: The list of human protein-coding genes used for filtering.
pathway_genesets <- HgProteinCodingGenes
saveRDS(pathway_genesets, "pathway_genesets.rds")