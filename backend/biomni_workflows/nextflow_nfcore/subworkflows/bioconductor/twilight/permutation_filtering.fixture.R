# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("stats", "splines", "golubEsets", "vsn", "twilight")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(stats)
library(splines)
library(golubEsets)
library(vsn)
library(twilight)

data(Golub_Train)
golubNorm <- justvsn(Golub_Train)
id <- as.numeric(Golub_Train$ALL.AML)

write.csv(exprs(golubNorm), "expression_matrix.csv", row.names = TRUE)
write.csv(data.frame(id = id), "phenotype_labels.csv", row.names = FALSE)