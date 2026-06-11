# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Biobase", "Heatplus")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Biobase)
library(Heatplus) # Not strictly needed for data prep, but good practice to load the main package

# Reproduce the vignette's data preparation
data(sample.ExpressionSet)
exdat = sample.ExpressionSet

# Extract the expression matrix that the workflow consumes
# The workflow reads `exprs_matrix.csv` and converts it to a matrix
# using `as.matrix(read.csv("exprs_matrix.csv", row.names = 1))`
raw_matrix_data <- exprs(exdat)

# Serialize the matrix to exprs_matrix.csv
# write.csv will write row names as the first column by default, which matches `row.names = 1`
write.csv(raw_matrix_data, "exprs_matrix.csv", row.names = TRUE)