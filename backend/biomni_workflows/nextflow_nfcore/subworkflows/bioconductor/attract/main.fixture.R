# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("attract")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(attract)

# Load the example datasets provided by the attract package
# These datasets are used directly in the vignette's data preparation.
data(exprs.dat)
data(samp.info)

# The workflow reads 'exprs.dat' as a space-separated table with header and row names.
# We need to save the 'exprs.dat' matrix in this exact format.
# `quote = FALSE` prevents character strings from being enclosed in quotes,
# which is typically desired for numeric data or simple factors/characters
# when `sep = ""` is used for reading.
write.table(exprs.dat, file = "exprs.dat", sep = " ", quote = FALSE, row.names = TRUE, col.names = TRUE)

# The workflow reads 'samp.info' as a space-separated table with header and row names.
# We need to save the 'samp.info' data frame in this exact format.
write.table(samp.info, file = "samp.info", sep = " ", quote = FALSE, row.names = TRUE, col.names = TRUE)