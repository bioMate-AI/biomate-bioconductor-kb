# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TENxVisiumData", "TabulaMurisSenisData", "SingleCellExperiment", "SpatialExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TENxVisiumData)
library(TabulaMurisSenisData)
library(SingleCellExperiment)
library(SpatialExperiment)

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

# Serialize the objects to RDS files
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
