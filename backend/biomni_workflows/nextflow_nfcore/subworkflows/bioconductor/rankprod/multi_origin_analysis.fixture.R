# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RankProd")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RankProd)

# Reproduce the vignette's data-preparation code
data(arab)

# Serialize the 'arab' object to multi_origin_expression_matrix.tsv
# The workflow reads this with read.delim(..., row.names = 1, check.names = FALSE)
# This implies a tab-separated file with row names in the first column.
write.table(arab, "multi_origin_expression_matrix.tsv", sep = "\t", quote = FALSE, row.names = TRUE, col.names = TRUE)

# Serialize the 'arab.cl' object to class_labels.txt
# The workflow reads this with scan(...)
# This implies a simple vector, one element per line.
writeLines(as.character(arab.cl), "class_labels.txt")

# Serialize the 'arab.origin' object to origin_labels.txt
# The workflow reads this with scan(...)
# This implies a simple vector, one element per line.
writeLines(as.character(arab.origin), "origin_labels.txt")