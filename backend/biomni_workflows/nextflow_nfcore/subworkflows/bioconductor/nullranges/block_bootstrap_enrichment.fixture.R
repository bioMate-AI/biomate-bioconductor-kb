# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("nullranges")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(nullranges)

# Create synthetic count matrix
mat <- matrix(rpois(100, lambda = 10), ncol = 10)
rownames(mat) <- paste0("gene", 1:10)
colnames(mat) <- paste0("sample", 1:10)

# Create synthetic coldata
coldata <- data.frame(
  sample = paste0("sample", 1:10),
  condition = rep(c("A", "B"), each = 5)
)

# Write to files
write.csv(mat, "matrix.csv", quote = FALSE)
write.csv(coldata, "coldata.csv", row.names = FALSE, quote = FALSE)