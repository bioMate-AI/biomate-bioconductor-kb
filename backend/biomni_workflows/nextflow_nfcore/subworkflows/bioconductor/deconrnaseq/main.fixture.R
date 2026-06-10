# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DeconRNASeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DeconRNASeq)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The DeconRNASeq vignette demonstrates loading example data using:
# data(mix.mtx)
# data(sig.mtx)
data(mix.mtx)
data(sig.mtx)

# 2. Serialize that object to EACH declared input file
# The workflow reads these files using:
# read.csv(..., header = TRUE, row.names = 1, check.names = FALSE, stringsAsFactors = FALSE)
# To match this, we write CSVs with row names included as the first column and a header.
# write.csv's default behavior (row.names = TRUE) achieves this.
write.csv(mix.mtx, "mixture_expression.csv", row.names = TRUE)
write.csv(sig.mtx, "signature_matrix.csv", row.names = TRUE)