# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggplot2", "SPOTlight", "SingleCellExperiment", "SpatialExperiment", "scater", "scran", "TENxVisiumData", "TabulaMurisSenisData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ggplot2)
library(SPOTlight)
library(SingleCellExperiment)
library(SpatialExperiment)
library(scater)
library(scran)
library(TENxVisiumData)
library(TabulaMurisSenisData)

# Load the spatial data:
spe <- MouseKidneyCoronal()
# Use symbols instead of Ensembl IDs as feature names
rownames(spe) <- rowData(spe)$symbol

# Load the single cell data.
sce <- TabulaMurisSenisDroplet(tissues = "Kidney")$Kidney

# Keep cells from 18m mice
sce <- sce[, sce$age == "18m"]
# Keep cells with clear cell type annotations
sce <- sce[, !sce$free_annotation %in% c("nan", "CD45")]

# Normalization procedure
sce <- logNormCounts(sce)

# Get vector indicating which genes are neither ribosomal or mitochondrial
genes <- !grepl(pattern = "^Rp[l|s]|Mt", x = rownames(sce))
dec <- modelGeneVar(sce, subset.row = genes)
hvg <- getTopHVGs(dec, n = 3000)

# Compute marker genes
colLabels(sce) <- colData(sce)$free_annotation
mgs <- scoreMarkers(sce, subset.row = genes)

# Save the prepared objects
saveRDS(sce, "sce.rds")
saveRDS(spe, "spe.rds")

# [biomate-fx-dual] emit each declared input under BOTH bare-token and .rds names
# so any input-staging harness collects the real serialized object under the
# exact name the workflow reads (bare token or <token>.rds).
.bm_dual <- function(b) {
  rds <- paste0(b, '.rds')
  if (file.exists(rds) && !file.exists(b)) file.copy(rds, b, overwrite=TRUE)
  if (file.exists(b) && !file.exists(rds)) file.copy(b, rds, overwrite=TRUE)
}
.bm_dual('sce')
.bm_dual('spe')
