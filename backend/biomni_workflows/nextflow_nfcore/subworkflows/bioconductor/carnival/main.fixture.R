# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CARNIVAL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CARNIVAL)

# Reproduce the vignette's data-preparation code to materialize the example objects.
# The vignette itself loads these objects from system.file, so we do the same
# to get the objects into the R environment.

# Load toy_perturbations_ex1
load(file = system.file("toy_perturbations_ex1.RData", package = "CARNIVAL"))
# This creates an object named 'toy_perturbations_ex1' in the environment.

# Load toy_measurements_ex1
load(file = system.file("toy_measurements_ex1.RData", package = "CARNIVAL"))
# This creates an object named 'toy_measurements_ex1' in the environment.

# Load toy_network_ex1
load(file = system.file("toy_network_ex1.RData", package = "CARNIVAL"))
# This creates an object named 'toy_network_ex1' in the environment.

# Serialize these objects to the declared input files in the exact format
# the workflow reads. Using save() to match the load() function used in
# the workflow excerpt.

save(toy_perturbations_ex1, file = "toy_perturbations_ex1.RData")
save(toy_measurements_ex1, file = "toy_measurements_ex1.RData")
save(toy_network_ex1, file = "toy_network_ex1.RData")