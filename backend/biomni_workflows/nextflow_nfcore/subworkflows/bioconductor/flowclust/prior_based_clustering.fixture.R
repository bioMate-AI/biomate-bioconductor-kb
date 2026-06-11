# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("flowClust", "flowCore")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(flowClust)
library(flowCore)

# Reproduce the vignette's data-preparation code
data(rituximab)

res1 <- flowClust(rituximab, varNames = c("FSC.H", "SSC.H"), K = 1, B = 100)

rituximab2 <- rituximab[rituximab %in% res1, ]

res2 <- flowClust(rituximab2, varNames = c("FL1.H", "FL3.H"), K = 1:6, B = 100)

# Serialize the objects to the declared input files
saveRDS(rituximab2, "rituximab2.rds")
saveRDS(res2, "res2.rds")