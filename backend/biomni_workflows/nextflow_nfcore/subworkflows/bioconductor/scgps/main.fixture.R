# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scGPS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scGPS)

# Load the dataset from the package
day2 <- day_2_cardio_cell_sample

# Extract components as described in the vignette
ExpressionMatrix <- day2$dat2_counts
GeneMetadata <- day2$dat2geneInfo
CellMetadata <- day2$dat2_clusters

# Serialize to the declared input files
saveRDS(ExpressionMatrix, "ExpressionMatrix")
saveRDS(GeneMetadata, "GeneMetadata")
saveRDS(CellMetadata, "CellMetadata")