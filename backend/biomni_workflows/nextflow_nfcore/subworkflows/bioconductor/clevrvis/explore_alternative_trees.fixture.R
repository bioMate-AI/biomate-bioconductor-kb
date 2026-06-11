# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clevRvis")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clevRvis)

timepoints <- c(0, 50, 100)
parents <- c(0, 1, 1, 3, 0, 5, 6)
fracTable <- matrix(c(20, 10, 0, 0, 0, 0, 0,
                      40, 20, 15, 0, 30, 10, 0,
                      50, 25, 15, 10, 40, 20, 15), ncol = length(timepoints))

saveRDS(fracTable, "fracTable.csv")
saveRDS(timepoints, "timepoints.csv")