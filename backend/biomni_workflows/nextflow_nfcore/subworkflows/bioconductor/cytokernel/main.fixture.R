# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("cytoKernel", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(cytoKernel)
library(SummarizedExperiment)

# Load the example dataset from the cytoKernel package
data("cytoHDBMW", package = "cytoKernel")

# Extract the expression matrix (features on rows, samples on columns)
expr_mat <- assay(cytoHDBMW, "exprs")

# Write the expression matrix to a CSV file
write.csv(as.data.frame(expr_mat), file = "expression_matrix.csv", row.names = TRUE)

# Create the binary categorical vector representing the group condition for each sample
# As used in the vignette: rep(c(0, 1), c(4, 4))
group_factor <- rep(c(0, 1), c(4, 4))

# Write the group labels to a CSV file
write.csv(data.frame(group = group_factor), file = "group_labels.csv", row.names = FALSE)