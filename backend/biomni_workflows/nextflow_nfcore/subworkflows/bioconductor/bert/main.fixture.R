# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BERT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BERT)

# Reproduce the vignette's data-preparation code
# The vignette's "Basic Usage" section uses generate_dataset from BERT
# to create test data for the BERT function.
dataset_raw <- generate_dataset(features=60, batches=10, samplesperbatch=10, mvstmt=0.1, classes=2)

# Serialize the object to expression_data.csv
# The workflow reads this file using read.csv("expression_data.csv", check.names = FALSE)
write.csv(dataset_raw, "expression_data.csv", row.names = FALSE)