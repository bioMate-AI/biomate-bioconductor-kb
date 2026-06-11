# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HTSFilter", "edgeR", "DESeq2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HTSFilter)
library(edgeR)
library(DESeq2) # Not strictly needed for data prep, but loaded in vignette

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data("sultan")

# 2. Serialize that object to EACH declared input file
# Extract counts matrix
counts_matrix <- Biobase::exprs(sultan)

# Extract sample metadata
sample_metadata <- Biobase::pData(sultan)

# Save counts_matrix to counts_matrix.csv
write.csv(counts_matrix, "counts_matrix.csv", row.names = TRUE, quote = FALSE)

# Save sample_metadata to sample_metadata.csv
write.csv(sample_metadata, "sample_metadata.csv", row.names = TRUE, quote = FALSE)