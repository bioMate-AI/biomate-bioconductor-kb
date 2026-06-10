# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("data.table", "DEWSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(data.table)
library(DEWSeq)

countFile <- "countFile.txt.gz"
annotationFile <- "annotationFile.txt.gz"
maxCountFile <- "maxCountFile.txt.gz"

# The DEWSeq vignette does not provide explicit R code for generating the input files.
# However, the DEWSeq function documentation describes the expected format for
# countData, annotationData, and maxCountData:
# - They must be data.tables/data.frames.
# - The first three columns must be 'chr', 'start', 'end'.
# - Subsequent columns are sample-specific counts/values or feature annotations.
# We create minimal dummy data conforming to these specifications to serve as a test fixture