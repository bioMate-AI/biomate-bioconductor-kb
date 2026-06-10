# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("edgeR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(edgeR)

set.seed(123)
Symbol <- paste0("Gene", 1:100)
Sample1 <- rnbinom(100, mu=100, size=2)
Sample2 <- rnbinom(100, mu=100, size=2)
Sample3 <- rnbinom(100, mu=500, size=2)
Sample4 <- rnbinom(100, mu=500, size=2)

TableOfCounts <- data.frame(Symbol, Sample1, Sample2, Sample3, Sample4, stringsAsFactors=FALSE)

write.table(TableOfCounts, file="TableOfCounts.txt", sep="\t", quote=FALSE, row.names=FALSE)