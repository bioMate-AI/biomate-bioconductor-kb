# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HTSFilter", "edgeR", "DESeq2", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HTSFilter)
library(edgeR)
library(DESeq2) # Not strictly needed for data prep, but loaded in vignette
library(Biobase) # For exprs and pData functions, implicitly loaded by HTSFilter

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data("sultan")

# 2. Serialize the object to declared input files
# Extract counts matrix
counts_data <- exprs(sultan)

# Extract sample metadata
sample_metadata <- pData(sultan)

# Save counts_data to counts_matrix.csv
# write.csv will include row names as the first column, which matches read.csv(..., row.names = 1)
# check.names = FALSE in read.csv is for column names, write.csv default behavior is fine.
write.csv(counts_data, "counts_matrix.csv", row.names = TRUE, quote = FALSE)

# Save sample_metadata to sample_metadata.csv
# write.csv will include row names as the first column, which matches read.csv(..., row.names = 1)
write.csv(sample_metadata, "sample_metadata.csv", row.names = TRUE, quote = FALSE)