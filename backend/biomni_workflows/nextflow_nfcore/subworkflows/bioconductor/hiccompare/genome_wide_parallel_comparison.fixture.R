# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HiCcompare")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HiCcompare)

# Reproduce the vignette's own data-preparation code
# Load the example sparse matrices for HMEC and NHEK cell lines on chromosome 22.
# These are 3-column data frames with 'region1', 'region2' (start coordinates), and 'IF'.
data("HMEC.chr22")
data("NHEK.chr22")

# The workflow's `read.table` expects a 7-column format:
# c("chr1", "start1", "end1", "chr2", "start2", "end2", "IF")
# The `HMEC.chr22` and `NHEK.chr22` objects are 3-column sparse matrices.
# The