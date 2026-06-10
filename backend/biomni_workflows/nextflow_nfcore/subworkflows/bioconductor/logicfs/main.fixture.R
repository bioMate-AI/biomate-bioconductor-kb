# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("logicFS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(logicFS)

# Load the dataset from the package
data(data.logicfs)

# Serialize the matrix of categorical SNP genotypes
write.table(data.logicfs, file = "data.logicfs", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)

# Serialize the vector of binary class labels
write.table(cl.logicfs, file = "cl.logicfs", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)