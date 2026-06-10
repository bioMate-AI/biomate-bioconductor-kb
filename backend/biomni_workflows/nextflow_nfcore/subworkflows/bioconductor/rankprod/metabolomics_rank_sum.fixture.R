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
data(Apples)

# Serialize apples.data.vsn to metabolite_intensity_matrix.tsv
# The workflow reads this with:
# as.matrix(read.delim("metabolite_intensity_matrix.tsv", row.names = 1, header = TRUE, check.names = FALSE))
# This implies a tab-separated file with row names as the first column and column names as a header.
write.table(apples.data.vsn, file = "metabolite_intensity_matrix.tsv",
            sep = "\t", quote = FALSE, col.names = TRUE, row.names = TRUE)

# Serialize apples.cl to class_labels.txt
# The workflow reads this with:
# as.numeric(scan("class_labels.txt", quiet = TRUE))
# This implies a file with numeric values, typically one per line or space-separated.
# Writing one value per line is a robust way to satisfy `scan`.
write.table(apples.cl, file = "class_labels.txt",
            sep = "\n", quote = FALSE, col.names = FALSE, row.names = FALSE)