# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("M3Drop", "M3DExampleData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(M3Drop)
library(M3DExampleData)

# Data preparation from vignette chunk 2
counts <- Mmus_example_list$data
labels <- Mmus_example_list$labels
total_features <- colSums(counts >= 0)
counts <- counts[,total_features >= 2000]
labels <- labels[total_features >= 2000]

# Save the prepared objects in the format the workflow reads
# The workflow can read RDS files for both counts and labels.
saveRDS(counts, "counts")
saveRDS(labels, "labels")