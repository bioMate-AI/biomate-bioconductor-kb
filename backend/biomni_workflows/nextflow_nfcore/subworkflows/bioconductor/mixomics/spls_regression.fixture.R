# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("mixOmics")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(mixOmics)

data("liver.toxicity")

# The liver toxicity dataset contains gene expression (X) and clinical measurements (Y)
predictor_matrix <- liver.toxicity$gene
response_matrix <- liver.toxicity$clinic

write.csv(predictor_matrix, file = "predictor_matrix.csv", row.names = TRUE)
write.csv(response_matrix, file = "response_matrix.csv", row.names = TRUE)