# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CiteFuse", "scater", "SingleCellExperiment", "DT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CiteFuse)
library(scater)
library(SingleCellExperiment)
library(DT)

# Reproduce the vignette's data preparation
data("CITEseq_example", package = "CiteFuse")

# Create the initial SingleCellExperiment object
sce_citeseq <- preprocessing(CITEseq_example)

# Apply HTO Normalisation and dimension reduction
sce_citeseq <- normaliseExprs(sce = sce_citeseq, altExp_name = "HTO", transform = "log")
sce_citeseq <- scater::runTSNE(sce_citeseq, altexp = "HTO", name = "TSNE_HTO", pca = TRUE)
sce_citeseq <- scater::runUMAP(sce_citeseq, altexp = "HTO", name = "UMAP_HTO")

# Perform cross-sample doublet detection
sce_citeseq <- crossSampleDoublets(sce_citeseq)

# Perform within-sample doublet detection
sce_citeseq <- withinSampleDoublets(sce_citeseq, minPts = 10)

# The workflow expects 'sce_citeseq' from 'sce_control.rds'.
# We use the 'sce_citeseq' object after all initial processing and doublet annotation,
# but before filtering out doublets.
saveRDS(sce_citeseq, "sce_control.rds")

# The workflow expects 'sce_ctcl_subset' from 'sce_disease.rds'.
# The vignette then filters 'sce_citeseq' to remove doublets.
# We will use this filtered object as 'sce_ctcl_subset'.
sce_ctcl_subset <- sce_citeseq[, sce_citeseq$doubletClassify_within_class == "Singlet" & sce_citeseq$doubletClassify_between_class == "Singlet"]

saveRDS(sce_ctcl_subset, "sce_disease.rds")