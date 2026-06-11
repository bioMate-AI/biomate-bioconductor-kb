# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SiPSiC", "SingleCellExperiment", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SiPSiC)
library(SingleCellExperiment)
library(Matrix)

geneCountsMatrix <- matrix(rpois(16, lambda = 10), ncol = 4, nrow = 4)
geneCountsMatrix <- as(geneCountsMatrix, "dgCMatrix")
rownames(geneCountsMatrix) <- c("Gene1", "Gene2", "Gene3", "Gene4")
colnames(geneCountsMatrix) <- c("Cell1", "Cell2", "Cell3", "Cell4")

pathwayGenesList <- c("Gene1", "Gene2", "Gene4")

saveRDS(geneCountsMatrix, "geneCountsMatrix.rds")
saveRDS(pathwayGenesList, "pathwayGenesList.txt")