# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellAlleleExperiment", "Matrix")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleCellAlleleExperiment)
library(Matrix)

# 1. Create cells_x_genes.barcodes.txt
barcodes <- c("AAACCCAAGGTAGTCG", "AAACCCACAATCCAGT", "TTTGTTGTCTGTACAG", "TTTGTTGTCTTCTAAC")
writeLines(barcodes, "cells_x_genes.barcodes.txt")

# 2. Create cells_x_genes.features.txt
features <- c(
  "ENSG00000279928.2",
  "ENSG00000228037.1",
  "A*02:01:01:01",
  "A*24:02:01:01",
  "B*15:01:01:01",
  "B*44:03:01:01",
  "C*03:03:01:01",
  "C*16:01:01:01"
)
writeLines(features, "cells_x_genes.features.txt")

# 3. Create cells_x_genes_mtx.mtx
mat <- sparseMatrix(
  i = c(1, 2, 3, 4, 5, 6, 7, 8),
  j = c(1, 1, 2, 2, 3, 3, 4, 4),
  x = c(10, 5, 2, 3, 1, 4, 6, 2),
  dims = c(length(features), length(barcodes))
)
writeMM(mat, "cells_x_genes_mtx.mtx")

# 4. Create lookup_table.csv
lookup <- data.frame(
  Allele = c("A*02:01:01:01", "A*24:02:01:01", "B*15:01:01:01", "B*44:03:01:01", "C*03:03:01:01", "C*16:01:01:01"),
  Gene = c("HLA-A", "HLA-A", "HLA-B", "HLA-B", "HLA-C", "HLA-C"),
  Function = c("HLA_class_I", "HLA_class_I", "HLA_class_I", "HLA_class_I", "HLA_class_I", "HLA_class_I")
)
write.csv(lookup, "lookup_table.csv", row.names = FALSE, quote = FALSE)