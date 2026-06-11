# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BEclear")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BEclear)

# Reproduce the vignette's data preparation
data("BEclearData")

# Serialize ex.data to beta_values.csv
# The workflow reads with row.names = 1, so write row names.
write.csv(ex.data, "beta_values.csv", row.names = TRUE)

# Serialize ex.samples to sample_metadata.csv
# The workflow reads without specifying row.names, so write without row names.
write.csv(ex.samples, "sample_metadata.csv", row.names = FALSE)