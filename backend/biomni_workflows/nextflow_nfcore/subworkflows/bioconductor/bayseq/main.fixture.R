# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("baySeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(baySeq)

# Reproduce the vignette's data-preparation code for 'simData'
# The vignette loads 'simData' directly using data()
data(simData)

# The workflow reads 'simData' from the working directory using
# read.csv, read.delim, or read.table, all with row.names = 1.
# This means the first column of the saved file should contain the row names.
# Saving as a CSV file with row names is a suitable format.
write.csv(simData, file = "simData", row.names = TRUE, quote = FALSE)