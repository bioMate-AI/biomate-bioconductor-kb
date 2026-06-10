# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("scMultiSim")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(scMultiSim)

data(GRN_params_100)

options <- list(
  GRN = GRN_params_100,
  num.cells = 100,
  num.cifs = 20,
  cif.sigma = 1,
  tree = Phyla5(),
  diff.cif.fraction = 0.8,
  do.velocity = FALSE
)

results <- sim_true_counts(options)

write.csv(results$counts, "counts.csv", row.names = TRUE)
write.csv(results$cell_meta, "coldata.csv", row.names = TRUE)