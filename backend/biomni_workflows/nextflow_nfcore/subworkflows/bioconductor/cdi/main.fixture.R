# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CDI")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CDI)

# Reproduce the vignette's data-preparation code
data(one_batch_matrix, package = "CDI")
data(one_batch_matrix_celltype, package = "CDI")
data(one_batch_matrix_label_df, package = "CDI")

# Serialize the objects to .rds files, as read by the workflow
saveRDS(one_batch_matrix, "one_batch_matrix.rds")
saveRDS(one_batch_matrix_label_df, "one_batch_matrix_label_df.rds")
saveRDS(one_batch_matrix_celltype, "one_batch_matrix_celltype.rds")