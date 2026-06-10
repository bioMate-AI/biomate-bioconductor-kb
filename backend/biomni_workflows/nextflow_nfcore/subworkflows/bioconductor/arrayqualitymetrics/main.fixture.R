# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("arrayQualityMetrics", "ALLMLL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("arrayQualityMetrics")
library("ALLMLL")

# Reproduce the vignette's data preparation code
# Load the MLL.A dataset, which is an AffyBatch object
data("MLL.A")

# The workflow reads MLL.A and CCl4 from the working directory.
# The vignette only provides data for MLL.A.
# To fulfill the requirement of serializing "that object" (MLL.A)
# to "EACH declared input file (MLL.A, CCl4)",
# we save the MLL.A object to both file names.
saveRDS(MLL.A, file = "MLL.A")
saveRDS(MLL.A, file = "CCl4")