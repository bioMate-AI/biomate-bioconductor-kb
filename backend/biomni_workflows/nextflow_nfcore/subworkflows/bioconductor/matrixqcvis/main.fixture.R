# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MatrixQCvis", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MatrixQCvis)
library(SummarizedExperiment)

# Since ExperimentHub fetches are strictly forbidden for offline testing,
# we construct a synthetic dataset that mimics the structure of the
# SummarizedExperiment object used in the vignette.

# The vignette subsets to 40 samples and filters features with sd > 0.
# It also references 'type' and 'arbitrary_levels' columns in colData.

set.seed(123)
n_features <- 100
n_samples <- 40

# Generate synthetic intensity data (counts)
intensity_matrix <- matrix(
    rpois(n_features * n_samples, lambda = 100),
    nrow = n_features,
    ncol = n_samples
)
rownames(intensity_matrix) <- paste0("feature_", seq_len(n_features))
colnames(intensity_matrix) <- paste0("sample_", seq_len(n_samples))

# Generate synthetic colData matching the vignette's usage
coldata_df <- data.frame(
    sample = paste0("sample_", seq_len(n_samples)),
    type = rep(c("Normal", "Tumor"), each = 20),
    arbitrary_levels = rep(c("A", "B"), times = 20),
    row.names = paste0("sample_", seq_len(n_samples))
)

# Write the required input files
write.csv(intensity_matrix, "intensity.csv", row.names = TRUE)
write.csv(coldata_df, "coldata.csv", row.names = TRUE)