# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CDI")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CDI)

# Reproduce the vignette's data-preparation code for multi-batch datasets
# These objects are provided as example data within the CDI package
data(two_batch_matrix, package = "CDI")
data(two_batch_matrix_batch, package = "CDI")
data(two_batch_matrix_label_df, package = "CDI")
data(two_batch_matrix_celltype, package = "CDI")

# Serialize the objects to the declared input files using saveRDS
# This matches the workflow's preference for readRDS as indicated by the load_input function
saveRDS(two_batch_matrix, "two_batch_matrix")
saveRDS(two_batch_matrix_batch, "two_batch_matrix_batch")
saveRDS(two_batch_matrix_label_df, "two_batch_matrix_label_df")
saveRDS(two_batch_matrix_celltype, "two_batch_matrix_celltype")