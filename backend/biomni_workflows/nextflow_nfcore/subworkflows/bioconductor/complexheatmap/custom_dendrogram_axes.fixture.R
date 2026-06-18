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
m = matrix(rnorm(1000*10), nr = 1000)
rownames(m) = paste0("row", 1:1000)
colnames(m) = paste0("col", 1:10)

# Workflow reads this with read.table(header=TRUE, row.names=1); write a tab table
# with a leading empty header cell (col.names=NA) so the row-name column aligns.
write.table(as.data.frame(m), "matrix", sep="\t", quote=FALSE, col.names=NA)