# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crisprScore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crisprScore)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette provides examples of constructing specific input sequences for various scoring methods,
# rather than a single pre-existing dataset for a CSV file.
# We will create a data frame containing these example sequences, suitable for a workflow
# that reads a CSV and then applies crisprScore functions.
# The column names are chosen to be descriptive and to align with common gRNA data structures.
# The 'sequence' column will hold the exact input strings as constructed in the vignette examples.

# Rule Set 1 / Rule Set 3 example (SpCas9)
flank5_rs1 <- "ACCT"
spacer_rs1 <- "