# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AIMS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AIMS)

# Load the example dataset from the AIMS package
data(mcgillExample)

# The workflow expects an expression matrix as a CSV.
# In the vignette, mcgillExample$D is initially a matrix before being converted to an ExpressionSet.
# The applyAIMS function description also states it expects a numerical matrix.
# We extract the original matrix from mcgillExample.
expression_matrix <- mcgillExample$D

# Write the expression matrix to expression_matrix.csv
# The workflow reads with `row.names = 1`, so we include row names in the output.
# The workflow reads with `check.names = FALSE`, so column names are preserved as-is.
write.csv(expression_matrix, "expression_matrix.csv", row.names = TRUE, quote = FALSE)

# The workflow expects gene annotations as a CSV, read into a data frame.
# mcgillExample$EntrezID is a character vector of Entrez IDs.
# We convert this vector into a single-column data frame for writing to CSV.
gene_annotations_df <- data.frame(EntrezID = mcgillExample$EntrezID)

# Write the gene annotations to gene_annotations.csv
# The workflow reads with `stringsAsFactors = FALSE`.
# We do not include row names for this annotation file.
write.csv(gene_annotations_df, "gene_annotations.csv", row.names = FALSE, quote = FALSE)