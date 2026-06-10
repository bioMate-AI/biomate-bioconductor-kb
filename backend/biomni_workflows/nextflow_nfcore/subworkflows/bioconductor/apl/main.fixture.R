# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("APL", "scRNAseq", "SingleCellExperiment", "scran", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(APL)
library(scRNAseq)
library(SingleCellExperiment)
library(scran)
library(scater)

set.seed(1234)

# Loading the data
darmanis <- DarmanisBrainData()

# Normalization, PCA & Clustering
set.seed(100)
clust <- quickCluster(darmanis)
darmanis <- computeSumFactors(darmanis, cluster = clust, min.mean = 0.1)
darmanis <- logNormCounts(darmanis)
dec <- modelGeneVar(darmanis)
top_darmanis <- getTopHVGs(dec, n = 5000)
darmanis <- fixedPCA(darmanis, subset.row = top_darmanis)
darmanis <- runUMAP(darmanis, dimred = "PCA")

# Save the processed object to the expected input file name
saveRDS(darmanis, file = "darmanis.rds")