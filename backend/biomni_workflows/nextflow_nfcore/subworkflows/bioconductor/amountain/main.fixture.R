# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AMOUNTAIN")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AMOUNTAIN)

# Reproduce the vignette's data-preparation code
n = 100
k = 20
theta = 0.5
pp <- networkSimulation(n, k, theta)

# Extract W and z as used by the analysis functions
W <- pp[[1]]
z <- pp[[2]]

# Serialize the objects to the specified input files using saveRDS
saveRDS(W, "W")
saveRDS(z, "z")