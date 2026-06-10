# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("twilight", "golubEsets", "vsn")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(twilight)
library(golubEsets)
library(vsn)

data(Golub_Train)
golubNorm <- justvsn(Golub_Train)
id <- as.numeric(Golub_Train$ALL.AML)

exprs_mat <- exprs(golubNorm)
write.csv(exprs_mat, "expression_matrix.csv", row.names = TRUE)

clin_param <- data.frame(Sample = colnames(exprs_mat), ALL.AML = id)
write.csv(clin_param, "clinical_parameter.csv", row.names = FALSE)