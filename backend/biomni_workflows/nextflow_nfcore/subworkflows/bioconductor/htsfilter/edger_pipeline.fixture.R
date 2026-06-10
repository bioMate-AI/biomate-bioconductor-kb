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
library(DESeq2)
library(Biobase) # For exprs() and pData() on ExpressionSet objects

# Reproduce the vignette's data-preparation code
data("sultan")

# Extract counts matrix
counts_data <- exprs(sultan)

# Extract sample metadata
metadata <- pData(sultan)

# Serialize to input files
write.csv(counts_data, "counts_matrix.csv", row.names = TRUE, quote = FALSE)
write.csv(metadata, "sample_metadata.csv", row.names = TRUE, quote = FALSE)