# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scMET", "data.table")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages(library(scMET))
suppressPackageStartupMessages(library(data.table))

if (!exists("scmet_dt")) {
    data("scmet_dt", package = "scMET")
}

write.csv(scmet_dt$Y, "single_cell_methylation.csv", row.names = FALSE, quote = FALSE)
write.csv(scmet_dt$X, "covariates.csv", row.names = TRUE, quote = FALSE)