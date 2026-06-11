# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("HTSFilter", "Biobase")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(HTSFilter)
library(Biobase) # For exprs() and pData() on ExpressionSet objects

# Reproduce the vignette's data-preparation code
data("sultan")

# Extract counts matrix and sample metadata
counts_matrix <- exprs(sultan)
sample_metadata <- pData(sultan)

# Serialize to CSV files in the exact format the workflow reads
write.csv(counts_matrix, "counts_matrix.csv", row.names = TRUE, quote = FALSE)
write.csv(sample_metadata, "sample_metadata.csv", row.names = TRUE, quote = FALSE)