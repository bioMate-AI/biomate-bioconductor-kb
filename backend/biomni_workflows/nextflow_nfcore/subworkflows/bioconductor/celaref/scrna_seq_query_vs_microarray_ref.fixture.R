# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("celaref")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(celaref)

# The provided vignette describes the *structure* of the input data (counts matrix,
# cell cluster assignments) but does not contain explicit R code using `data()`,
# `system.file()`, or a generator function to create these objects.
#
# Therefore, to fulfill the requirement of generating test fixture files,
# minimal dummy data is created here, adhering to the described formats.
# This approach is taken because the prompt guarantees data-preparation code
# exists in the vignette, but it is absent in the provided text.

# 1. Create dummy counts matrix for the query dataset
# Based on vignette's description: "A counts matrix of number of reads per gene, per cell."
# Example structure shown: genes as rows, cells as columns.
counts_matrix_query <- matrix(
  c(0, 1, 0, 1,
    0, 3, 0, 2,
    1, 40, 1, 0),
  nrow = 3, byrow = TRUE,
  dimnames = list(
    c("GeneA", "GeneB", "GeneC"),
    c("Cell1", "Cell2", "Cell3", "Cell4")
  )
)

# 2. Create dummy cell information data frame for the query dataset
# Based on vignette's description: "Cluster assignment for each cell."
# Example structure shown: CellId and Cluster columns.
cell_info_df_query <- data.frame(
  CellId = c("Cell1", "Cell2", "Cell3", "Cell4"),
  Cluster = c("cluster1", "cluster1", "cluster2", "cluster2"),
  stringsAsFactors = FALSE
)

# 3. Create dummy normalized expression matrix
# This input file is listed in the prompt but not explicitly described in the
# vignette's data preparation section. Assuming it's a matrix of normalized
# expression values (e.g., log-transformed counts) for the query cells.
norm_expression_matrix <- log1p(counts_matrix_query) # Simple log1p transformation for example

# 4. Create dummy samples data frame
# This input file is listed in the prompt but not explicitly described in the
# vignette's data preparation section. Assuming it's metadata for the query cells/samples.
samples_df <- data.frame(
  SampleId = c("Cell1", "Cell2", "Cell3", "Cell4"), # Using cell IDs as sample IDs for simplicity
  Batch = c("Batch1", "Batch1", "Batch2", "Batch2"),
  stringsAsFactors = FALSE
)

# Serialize objects to the specified input files
# The workflow's read method is not specified in the empty R excerpt provided.
# Tab-separated files (`.tsv`) are a common format for "flat files" in bioinformatics.
# `col.names = NA` for matrices ensures the row names are written as the first column
# without a header for that column, which is standard for matrix exports.
# `row.names = FALSE` for data frames prevents R's default row numbers from being written.
write.table(counts_matrix_query, file = "counts_filepath.query", sep = "\t", quote = FALSE, col.names = NA)
write.table(cell_info_df_query, file = "cell_info_filepath.query", sep = "\t", quote = FALSE, row.names = FALSE)
write.table(norm_expression_matrix, file = "norm_expression_file", sep = "\t", quote = FALSE, col.names = NA)
write.table(samples_df, file = "samples_file", sep = "\t", quote = FALSE, row.names = FALSE)