# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SummarizedExperiment", "BERT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SummarizedExperiment)
library(BERT)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette provides an example of creating a SummarizedExperiment object
# which includes 'Batch' and 'Reference' columns in its colData.
# This is chosen as the basis because the input file name
# 'expression_data_with_references.csv' implies the presence of a 'Reference' column.

nrows <- 200
ncols <- 8
expr_values <- matrix(runif(nrows * ncols, 1, 1e4), nrows)

# Add feature names to the expression matrix for clarity in the CSV output
rownames(expr_values) <- paste0("feature_", 1:nrows)
# Add sample names to the expression matrix columns
colnames(expr_values) <- paste0("sample_", 1:ncols)

# Create colData as shown in the vignette
colData <- data.frame(Batch=c(1,1,1,1,2,2,2,2), Reference=c(1,1,0,0,1,1,0,0))
# Add sample names to colData to ensure correct alignment with expression data
rownames(colData) <- paste0("sample_", 1:ncols)

# The workflow reads a CSV file into a data.frame using read.csv(input_file, check.names = FALSE).
# BERT expects a data.frame with samples in rows and features in columns,
# with metadata columns (like Batch, Reference) included in the same data.frame.

# Transpose the expression matrix so samples are in rows and features are in columns.
expr_data_transposed <- as.data.frame(t(expr_values))

# Combine the transposed expression data with the colData (metadata).
# Ensure row names match for correct combination.
if (!all(rownames(expr_data_transposed) == rownames(colData))) {
  stop("Sample names in expression data and colData do not match, which is required for cbind.")
}
final_dataframe <- cbind(expr_data_transposed, colData)

# Add a 'Sample' column from the row names. The vignette states that a 'Sample'
# column can be present and is ignored by BERT, making the CSV self-describing.
final_dataframe$Sample <- rownames(final_dataframe)

# Reorder columns to place metadata columns (Sample, Batch, Reference) at the beginning
# for better readability, matching typical data layouts.
metadata_cols <- c("Sample", "Batch", "Reference")
feature_cols <- setdiff(colnames(final_dataframe), metadata_cols)
final_dataframe <- final_dataframe[, c(metadata_cols, feature_cols)]

#