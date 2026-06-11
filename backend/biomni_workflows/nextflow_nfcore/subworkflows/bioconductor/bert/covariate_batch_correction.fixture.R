# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BERT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BERT)

# Reproduce the vignette's own data-preparation code
# This call is found in Section 4 "Basic Usage" of the vignette
dataset_raw <- BERT::generate_dataset(features=60, batches=10, samplesperbatch=10, mvstmt=0.1, classes=2)

# Serialize the object to the declared input file
# The workflow reads this as a CSV, so write it as such.
# row.names = FALSE is crucial to prevent an extra column of row numbers.
write.csv(dataset_raw, "expression_data_with_covariates.csv", row.names = FALSE)