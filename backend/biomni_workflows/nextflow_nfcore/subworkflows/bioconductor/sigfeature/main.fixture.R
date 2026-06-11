# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("sigFeature", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(sigFeature)
library(SummarizedExperiment)

data(ExampleRawData, package="sigFeature")

expr_mat <- assays(ExampleRawData)$counts
write.csv(expr_mat, file="expression_matrix.csv", row.names=TRUE)

sample_meta <- as.data.frame(colData(ExampleRawData))
write.csv(sample_meta, file="sample_metadata.csv", row.names=TRUE)