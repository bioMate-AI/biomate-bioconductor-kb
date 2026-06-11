# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RAREsim")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RAREsim)

# Load the target data for the number of variants
data("nvariant_afr", package = "RAREsim")

# Write to the expected input file
write.csv(nvariant_afr, "nvariant_target.csv", row.names = FALSE)

# Load the target data for the allele frequency spectrum (AFS)
data("afs_afr", package = "RAREsim")

# Write to the expected input file
write.csv(afs_afr, "afs_target.csv", row.names = FALSE)