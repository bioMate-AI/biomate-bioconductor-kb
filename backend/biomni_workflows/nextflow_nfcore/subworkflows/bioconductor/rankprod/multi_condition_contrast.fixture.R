# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RankProd")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RankProd)

# Reproduce the vignette's data-preparation code.
# The `data(arab)` call loads the example dataset, which includes
# the 'arab' expression matrix, 'arab.cl' class labels, and 'arab.origin' origin labels.
data(arab)

# Serialize the 'arab' expression matrix to "multi_origin_expression_matrix.tsv".
# The workflow reads this as a tab-separated matrix with row names in the first column.
write.table(arab,
            file = "multi_origin_expression_matrix.tsv",
            sep = "\t",
            quote = FALSE,
            row.names = TRUE,
            col.names = NA) # NA for col.names ensures a blank cell at the top-left,
                            # which matches read.delim(..., row.names = 1)

# Serialize the 'arab.cl' class labels to "class_labels.txt".
# The workflow reads this using `scan`, which expects a vector of values.
# Writing each value on a new line is a robust format for `scan`.
cat(arab.cl, file = "class_labels.txt", sep = "\n")

# Serialize the 'arab.origin' origin labels to "origin_labels.txt".
# The workflow reads this using `scan`, which expects a vector of values.
# Writing each value on a new line is a robust format for `scan`.
cat(arab.origin, file = "origin_labels.txt", sep = "\n")