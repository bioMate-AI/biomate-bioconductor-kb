# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("twilight", "golubEsets", "vsn")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(twilight)
library(golubEsets)
library(vsn)

# Load the dataset used in the vignette
data(Golub_Train)

# Normalize the expression data on an additive scale as done in the vignette
golubNorm <- justvsn(Golub_Train)

# Extract the binary condition labels
id <- as.numeric(Golub_Train$ALL.AML)

# Write the normalized expression matrix to CSV
write.csv(exprs(golubNorm), file = "expression_matrix.csv", row.names = TRUE)

# Write the phenotype labels to CSV
write.csv(data.frame(id = id), file = "phenotype_labels.csv", row.names = FALSE)