# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ClusterFoldSimilarity", "Seurat", "scRNAseq", "dplyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ClusterFoldSimilarity)
library(Seurat)
library(scRNAseq)
library(dplyr)

# Human pancreatic single cell data 1
pancreasMuraro <- scRNAseq::MuraroPancreasData(ensembl=FALSE)
pancreasMuraro <- pancreasMuraro[,rownames(colData(pancreasMuraro)[!is.na(colData(pancreasMuraro)$label),])]
colData(pancreasMuraro)$cell.type <- colData(pancreasMuraro)$label
rownames(pancreasMuraro) <- make.names(unlist(lapply(strsplit(rownames(pancreasMuraro), split="__"), function(x)x[[1]])), unique = TRUE)
singlecell1Seurat <- CreateSeuratObject(counts=counts(pancreasMuraro), meta.data=as.data.frame(colData(pancreasMuraro)))

# Human pancreatic single cell data 2
pancreasBaron <- scRNAseq::BaronPancreasData(which="human", ensembl=FALSE)
colData(pancreasBaron)$cell.type <- colData(pancreasBaron)$label
rownames(pancreasBaron) <- make.names(rownames(pancreasBaron), unique = TRUE)
singlecell2Seurat <- CreateSeuratObject(counts=counts(pancreasBaron), meta.data=as.data.frame(colData(pancreasBaron)))

# Create a list with the unprocessed single-cell datasets
singlecellObjectList <- list(singlecell1Seurat, singlecell2Seurat)

# Apply the same processing to each dataset and return a list of single-cell analysis
singlecellObjectList <- lapply(X=singlecellObjectList, FUN=function(scObject){
  scObject <- NormalizeData(scObject)
  scObject <- FindVariableFeatures(scObject, selection.method="vst", nfeatures=2000)
  scObject <- ScaleData(scObject, features=VariableFeatures(scObject))
  scObject <- RunPCA(scObject, features=VariableFeatures(object=scObject))
  scObject <- FindNeighbors(scObject, dims=seq(16))
  scObject <- FindClusters(scObject, resolution=0.4)
})

# Serialize the object to the expected input file
saveRDS(singlecellObjectList, "singlecellObjectList.RDS")