# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("glmGamPoi", "SingleCellExperiment", "muscData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(glmGamPoi)
library(SingleCellExperiment)
library(muscData)

sce <- muscData::Kang18_8vs8()

set.seed(1)
sce_subset <- sce[rowSums(counts(sce)) > 100, sample(which(sce$multiplets == "singlet" & ! is.na(sce$cell) & sce$cell %in% c("CD4 T cells", "B cells", "NK cells")), 1000)]

counts(sce_subset) <- as.matrix(counts(sce_subset))
sce_subset$cell <- droplevels(sce_subset$cell)

saveRDS(sce_subset, "sce_subset.rds")