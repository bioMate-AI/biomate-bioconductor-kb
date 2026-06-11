# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("quantiseqr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(quantiseqr)

# Reproduce the vignette's data-preparation code
# Use case 1: Metastatic melanoma patients (Racle et al 2017)
# The vignette loads `dataset_racle` which contains `expr_mat`.
data("dataset_racle")

# Extract the expression matrix
expr_mat <- dataset_racle$expr_mat

# Serialize the object to expression_matrix.txt
# The workflow reads with:
# read.table(input_file, header = TRUE, sep = "\t", row.names = 1, check.names = FALSE)
# To match this, we need to write row names, column names, and use tab separation.
# quote = FALSE is important to prevent character strings (like gene names) from being quoted.
write.table(expr_mat, 
            file = "expression_matrix.txt", 
            sep = "\t", 
            row.names = TRUE, 
            col.names = TRUE, 
            quote = FALSE)