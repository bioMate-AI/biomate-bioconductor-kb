# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("consensus")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(consensus)
data("TCGA")

# The workflow reads matrix1.csv, matrix2.csv, matrix3.csv.
# The vignette loads U133A, Huex, Agilent, RNASeq.
# We will use U133A, Huex, and Agilent as the three input matrices.
# The workflow reads them using:
# as.matrix(read.csv(matrix_file, row.names = 1, check.names = FALSE))
# This implies the CSV files should have row names as the first column
# and numeric data in subsequent columns. `quote = FALSE` is used to
# prevent quoting of numeric values and row names, ensuring `read.csv`
# interprets them correctly as numbers and character row names.

write.csv(U133A, "matrix1.csv", row.names = TRUE, quote = FALSE)
write.csv(Huex, "matrix2.csv", row.names = TRUE, quote = FALSE)
write.csv(Agilent, "matrix3.csv", row.names = TRUE, quote = FALSE)