# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("glmGamPoi", "SingleCellExperiment", "muscData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(glmGamPoi)
    library(SingleCellExperiment)
    library(muscData)
})

# Load the dataset from the companion ExperimentData package as per the vignette
sce <- muscData::Kang18_8vs8()

set.seed(1)
# Take highly expressed genes and proper cells:
sce_subset <- sce[rowSums(counts(sce)) > 100, sample(which(sce$multiplets == "singlet" & ! is.na(sce$cell) & sce$cell %in% c("CD4 T cells", "B cells", "NK cells")), 1000)]

# Convert counts to dense matrix
counts(sce_subset) <- as.matrix(counts(sce_subset))

# Remove empty levels because glm_gp() will complain otherwise
sce_subset$cell <- droplevels(sce_subset$cell)

# Serialize the object to the expected input file
saveRDS(sce_subset, "sce.rds")