# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CARNIVAL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CARNIVAL)

# Reproduce the vignette's data-preparation code
# The vignette loads example data files that are internal to the CARNIVAL package.
# We load them to materialize the objects in the current environment.
load(file = system.file("toy_perturbations_ex1.RData", package = "CARNIVAL"))
load(file = system.file("toy_measurements_ex1.RData", package = "CARNIVAL"))
load(file = system.file("toy_network_ex1.RData", package = "CARNIVAL"))

# Serialize the materialized objects to the declared input files
save(toy_perturbations_ex1, file = "toy_perturbations_ex1.RData")
save(toy_measurements_ex1, file = "toy_measurements_ex1.RData")
save(toy_network_ex1, file = "toy_network_ex1.RData")