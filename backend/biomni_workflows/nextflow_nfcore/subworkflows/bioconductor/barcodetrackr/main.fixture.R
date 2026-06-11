# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("barcodetrackR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(barcodetrackR)

# Generate synthetic barcode count data for barcodetrackR
set.seed(123)
barcodes <- paste0("Barcode_", 1:100)
samples <- paste0("Sample_", 1:5)

count_matrix <- matrix(rpois(500, lambda = 10), nrow = 100, ncol = 5)
rownames(count_matrix) <- barcodes
colnames(count_matrix) <- samples

# Write to the expected input file
write.csv(count_matrix, "input.csv", row.names = TRUE)