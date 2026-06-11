# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BUSseq", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BUSseq)
library(SingleCellExperiment)

# Load the example data object from the BUSseq package
data(BUSseqfits_example)

# Extract the count data matrix
CountData_matrix <- assay(BUSseqfits_example, "counts")

# Extract the batch metadata
batch_metadata_df <- as.data.frame(colData(BUSseqfits_example))

# Write the count data to raw_counts.csv
# The workflow reads this with row.names = 1, so we include row names in the output.
# check.names = FALSE means column names should be preserved as-is.
write.csv(CountData_matrix, "raw_counts.csv", row.names = TRUE, quote = FALSE)

# Write the batch metadata to batch_metadata.csv
# The workflow reads this without row.names = 1, so the row names (Cell IDs)
# will become the first column in the resulting data frame.
# stringsAsFactors = FALSE means character columns should not be converted to factors.
write.csv(batch_metadata_df, "batch_metadata.csv", row.names = TRUE, quote = FALSE)