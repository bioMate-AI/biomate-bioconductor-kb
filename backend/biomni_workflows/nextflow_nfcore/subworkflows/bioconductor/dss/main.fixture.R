# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DSS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DSS)

set.seed(123)
counts1 = matrix(rnbinom(300, mu=10, size=10), ncol=3)
counts2 = matrix(rnbinom(300, mu=50, size=10), ncol=3)
X1 = cbind(counts1, counts2)
X2 = matrix(rnbinom(11400, mu=10, size=10), ncol=6)
X = rbind(X1,X2)
rownames(X) = paste0("gene", 1:nrow(X))
colnames(X) = paste0("sample", 1:ncol(X))

designs = c(0,0,0,1,1,1)

write.table(X, file="counts.txt", sep="\t", quote=FALSE, row.names=TRUE, col.names=TRUE)
write.table(designs, file="designs.txt", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)