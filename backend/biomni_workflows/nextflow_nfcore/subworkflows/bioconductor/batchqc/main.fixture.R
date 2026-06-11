# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BatchQC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BatchQC)

# Reproduce the vignette's data-preparation code
# Using Example 2 / Example Usage section for direct assignment to 'features' and 'metadata'
data(signature_data)
data(batch_indicator)

# The workflow reads 'features' and 'metadata' files.
# The R excerpt shows `read.delim` or `read.csv` with `row.names = 1, check.names = FALSE`.
# This implies writing row names as the first column and preserving original column names.
# Using write.csv for compatibility with read.csv, and ensuring row names are written.
# quote = FALSE is often safer for data files to prevent unintended quoting of numeric values.

# Serialize signature_data to 'features' file
write.csv(signature_data, file = "features", row.names = TRUE, quote = FALSE)

# Serialize batch_indicator to 'metadata' file
write.csv(batch_indicator, file = "metadata", row.names = TRUE, quote = FALSE)