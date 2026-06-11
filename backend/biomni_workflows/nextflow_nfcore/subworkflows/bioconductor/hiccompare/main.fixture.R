# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HiCcompare")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HiCcompare)

# Reproduce the vignette's data-preparation code
data("HMEC.chr22")
data("NHEK.chr22")

# Serialize the objects to the declared input files in the expected format
# The workflow reads with read.table, expecting tab-separated values.
# The vignette's head() output shows column names, so write with col.names = TRUE.
write.table(HMEC.chr22, file = "HMEC.chr22", sep = "\t", row.names = FALSE, col.names = TRUE)
write.table(NHEK.chr22, file = "NHEK.chr22", sep = "\t", row.names = FALSE, col.names = TRUE)