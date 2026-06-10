# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "Heatplus")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(Heatplus) # As requested, load the main package for the workflow

# Reproduce the vignette's data-preparation code
data(sample.ExpressionSet)
exdat <- sample.ExpressionSet

# Extract the expression matrix and sample metadata
exprs_matrix <- exprs(exdat)
sample_metadata <- pData(exdat)

# Serialize the objects to CSV files in the exact format the workflow reads
# write.csv by default includes row names as the first column, which matches
# the workflow's read.csv(..., row.names = 1, ...)
# Column names are preserved, matching check.names = FALSE
write.csv(exprs_matrix, "exprs_matrix.csv", row.names = TRUE)
write.csv(sample_metadata, "sample_metadata.csv", row.names = TRUE)