# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("topologyGSA")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(topologyGSA)
data(examples)

colnames(y1) <- paste("SYMBOL", colnames(y1), sep = ":")
colnames(y2) <- paste("SYMBOL", colnames(y2), sep = ":")

write.table(y1, file = "y1.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)
write.table(y2, file = "y2.txt", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)