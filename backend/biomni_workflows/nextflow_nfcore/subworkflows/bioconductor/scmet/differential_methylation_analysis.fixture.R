# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scMET", "data.table")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(scMET))
suppressPackageStartupMessages(library(data.table))

# Load the synthetic dataset provided by the scMET package
data("scmet_dt", package = "scMET")

# Extract the methylation data (long-format data.table)
Y <- scmet_dt$Y

# Split cells into two groups to create Group A and Group B
cells <- unique(Y$Cell)
half_idx <- length(cells) %/% 2
cells_A <- cells[1:half_idx]
cells_B <- cells[(half_idx + 1):length(cells)]

Y_A <- Y[Y$Cell %in% cells_A, ]
Y_B <- Y[Y$Cell %in% cells_B, ]

# Write methylation data to CSV
write.csv(Y_A, "group_A_methylation.csv", row.names = FALSE)
write.csv(Y_B, "group_B_methylation.csv", row.names = FALSE)

# Extract the feature-specific covariates matrix
X <- scmet_dt$X
X_df <- data.frame(Feature = rownames(X), X, stringsAsFactors = FALSE)

# Write covariates data to CSV
write.csv(X_df, "group_A_covariates.csv", row.names = FALSE)
write.csv(X_df, "group_B_covariates.csv", row.names = FALSE)