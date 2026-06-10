# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CaDrA", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CaDrA)
library(SummarizedExperiment)

# Reproduce the vignette's data-preparation code
# Load pre-simulated feature set
data(sim_FS)
# Load pre-computed input-score
data(sim_Scores)

# Serialize sim_FS to binary_features.csv
# The workflow reads binary_features.csv with row.names = 1, header = TRUE.
# This means the first column of the CSV should be the feature names (row names of the matrix),
# and the subsequent columns should be the sample names (column names of the matrix).
binary_features_matrix <- SummarizedExperiment::assay(sim_FS)
write.csv(binary_features_matrix, file = "binary_features.csv", row.names = TRUE, quote = FALSE)

# Serialize sim_Scores to functional_scores.csv
# The workflow reads functional_scores.csv with row.names = 1, header = TRUE.
# This means the first column of the CSV should be the sample names (names of the vector),
# and the second column should be the scores.
functional_scores_df <- data.frame(score = sim_Scores)
write.csv(functional_scores_df, file = "functional_scores.csv", row.names = TRUE, quote = FALSE)