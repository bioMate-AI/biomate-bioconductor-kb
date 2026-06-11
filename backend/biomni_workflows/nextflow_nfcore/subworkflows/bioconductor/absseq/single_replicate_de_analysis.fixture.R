# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ABSSeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ABSSeq)

# Reproduce the vignette's data preparation to materialize the counts matrix.
# The vignette uses `data(simuN5)` which contains the `counts` matrix.
data(simuN5)

# The workflow reads a counts matrix from 'counts_no_replicates.tsv'.
# The vignette's `simuN5$counts` is the exact counts matrix used in the examples.
counts_matrix <- simuN5$counts

# Serialize the counts matrix to 'counts_no_replicates.tsv'
# in the exact format the workflow reads:
# as.matrix(read.table(input_file, header = TRUE, sep = "\t", row.names = 1, check.names = FALSE))
# This requires a tab-separated file with a header and row names as the first column.
write.table(counts_matrix,
            file = "counts_no_replicates.tsv",
            sep = "\t",
            row.names = TRUE,
            col.names = TRUE,
            quote = FALSE)