# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ComplexHeatmap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ComplexHeatmap)

set.seed(123)
# Reproduce the vignette's data preparation
m = matrix(rnorm(1000*10), nr = 1000)
rownames(m) = paste0("row", 1:1000)
colnames(m) = paste0("col", 1:10)

# Serialize the object to the declared input file
# Since the read excerpt is empty, we default to a standard tab-delimited format
write.table(m, file = "matrix", sep = "\t", quote = FALSE, col.names = NA)