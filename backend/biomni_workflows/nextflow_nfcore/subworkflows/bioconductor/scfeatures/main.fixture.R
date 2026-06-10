# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scFeatures")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scFeatures)

# Load the example dataset provided by the package
data("example_scrnaseq", package = "scFeatures")

# Extract the normalized expression matrix and save as RDS
expression_matrix <- example_scrnaseq@assays$RNA@data
saveRDS(expression_matrix, "expression_matrix.rds")

# Extract the cell-level metadata (containing sample and celltype) and save as CSV
metadata <- example_scrnaseq@meta.data
write.csv(metadata, "metadata.csv", row.names = TRUE)