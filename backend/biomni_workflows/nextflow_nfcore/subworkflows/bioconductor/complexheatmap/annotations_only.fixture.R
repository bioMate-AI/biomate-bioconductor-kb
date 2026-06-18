# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ComplexHeatmap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ComplexHeatmap)

# Generate the numeric matrix as shown in the vignette
set.seed(123)
m <- matrix(rnorm(1000 * 10), nr = 1000)

# Workflow reads this with read.table(header=FALSE); write a headerless, no-rowname
# whitespace table (a saveRDS blob is not parseable by read.table).
write.table(m, "matrix", row.names=FALSE, col.names=FALSE, quote=FALSE)