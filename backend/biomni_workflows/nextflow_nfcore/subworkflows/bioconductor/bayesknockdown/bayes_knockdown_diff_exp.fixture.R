# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BayesKnockdown")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BayesKnockdown)

# Set seed for reproducibility as seen in other vignette examples
set.seed(1618)

# Reproduce the data generation code from the vignette for BayesKnockdown.diffExp
n1 <- 25
n2 <- 30
p <- 10

y1_matrix <- matrix(nrow = p, data = rnorm(n1 * p))
y2_matrix <- matrix(nrow = p, data = rnorm(n2 * p))

# Introduce the simulated difference for gene 3, as per the vignette
y2_matrix[3, ] <- y2_matrix[3, ] + 1

# Convert matrices to data frames for writing to CSV
# Default row names for matrices (1, 2, ..., p) will be used.
# Default column names for matrices (V1, V2, ..., Vn) will be used.
y1_df <- as.data.frame(y1_matrix)
y2_df <- as.data.frame(y2_matrix)

# Write the data frames to CSV files in the specified format.
# row.names = TRUE ensures the row names are written as the first column,
# matching the workflow's read.csv(..., row.names = 1, ...) call.
write.csv(y1_df, "condition1_matrix.csv", row.names = TRUE)
write.csv(y2_df, "condition2_matrix.csv", row.names = TRUE)