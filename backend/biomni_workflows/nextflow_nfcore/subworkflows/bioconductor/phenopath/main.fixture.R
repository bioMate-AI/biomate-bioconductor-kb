# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("phenopath")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressPackageStartupMessages({
    library(phenopath)
})

set.seed(123L)
sim <- simulate_phenopath()

# Write expression matrix (samples as rows, genes as columns)
write.csv(sim$y, "expression_matrix.csv", row.names = FALSE)

# Write covariates (sample-specific covariates)
write.csv(data.frame(x = sim$x), "covariates.csv", row.names = FALSE)