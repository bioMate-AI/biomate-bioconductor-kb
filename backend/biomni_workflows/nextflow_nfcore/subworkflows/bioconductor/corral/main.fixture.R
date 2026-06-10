# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("corral", "SingleCellExperiment", "CellBench", "MultiAssayExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(corral)
library(SingleCellExperiment)
library(CellBench)
library(MultiAssayExperiment)

# Reproduce the VIGNETTE'S OWN data-preparation code
scmix_dat <- CellBench::load_all_data()[1:3]

platforms <- c('10X','CELseq2','Dropseq')
for(i in seq_along(scmix_dat)) {
  colData(scmix_dat[[i]])$Method <- rep(platforms[i], ncol(scmix_dat[[i]]))
}

scmix_mae <- as(scmix_dat,'MultiAssayExperiment')
scmix_dat <- as.list(MultiAssayExperiment::experiments(MultiAssayExperiment::intersectRows(scmix_mae)))

# Remove 'non_ERCC_percent' column from colData of the second SCE object
# to allow successful concatenation (cbind)
colData(scmix_dat[[2]])$non_ERCC_percent <- NULL

# Combine the SingleCellExperiment objects into a single SCE
scmix_sce <- SingleCellExperiment::cbind(scmix_dat[[1]], scmix_dat[[2]], scmix_dat[[3]])

# Serialize the SingleCellExperiment object to zm4eq.sce
saveRDS(scmix_sce, "zm4eq.sce")

# Extract the counts matrix from the combined SingleCellExperiment object
zm4eq.countmat <- counts(scmix_sce)

# Serialize the count matrix to zm4eq.countmat
saveRDS(zm4eq.countmat, "zm4eq.sce")