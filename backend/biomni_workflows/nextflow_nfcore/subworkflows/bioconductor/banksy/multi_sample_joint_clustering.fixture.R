# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Banksy", "SummarizedExperiment", "SpatialExperiment", "Seurat", "scater", "cowplot", "ggplot2", "spatialLIBD", "ExperimentHub")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Banksy)
library(SummarizedExperiment)
library(SpatialExperiment)
library(Seurat)
library(scater)
library(cowplot)
library(ggplot2)
library(spatialLIBD)
library(ExperimentHub)

ehub <- ExperimentHub::ExperimentHub()
spe <- spatialLIBD::fetch_data(type = "spe", eh = ehub)

imgData(spe) <- NULL
assay(spe, "logcounts") <- NULL
reducedDims(spe) <- NULL
rowData(spe) <- NULL
colData(spe) <- DataFrame(
    sample_id = spe$sample_id,
    clust_annotation = factor(
        addNA(spe$layer_guess_reordered_short),
        exclude = NULL,
        labels = seq(8)
    ),
    in_tissue = spe$in_tissue,
    row.names = colnames(spe)
)
invisible(gc())

sample_names <- as.character(151673:151676)
spe_list <- lapply(sample_names, function(x) spe[, spe$sample_id == x])
rm(spe)
invisible(gc())

# Normalize data
seu_list <- lapply(spe_list, function(x) {
    x <- as.Seurat(x, data = NULL)
    NormalizeData(x, scale.factor = 5000, normalization.method = 'RC')
})
# Compute HVGs
hvgs <- lapply(seu_list, function(x) {
    VariableFeatures(FindVariableFeatures(x, nfeatures = 2000))
})
hvgs <- Reduce(union, hvgs)
# Add data to SpatialExperiment and subset to HVGs
aname <- "normcounts"
spe_list <- Map(function(spe, seu) {
    assay(spe, aname) <- GetAssayData(seu)
    spe[hvgs,]
}, spe_list, seu_list)
rm(seu_list)
invisible(gc())

saveRDS(spe_list, "spe_list.rds")