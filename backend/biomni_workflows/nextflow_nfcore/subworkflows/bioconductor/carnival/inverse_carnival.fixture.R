# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CARNIVAL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CARNIVAL)

# Reproduce the vignette's data-preparation code for toy_measurements_ex2 and toy_network_ex2
# Load initial data from the package's extdata
load(file = system.file("toy_measurements_ex2.RData", package = "CARNIVAL"))
load(file = system.file("toy_network_ex2.RData", package = "CARNIVAL"))

# Apply transformations as shown in the vignette for "Toy Example - 2"
# The vignette explicitly redefines toy_measurements_ex2
toy_measurements_ex2 <- c("M1" = 1, "M2" = 1, "M3" = 1)

# The vignette transforms toy_network_ex2
toy_network_ex2 <- as.data.frame(toy_network_ex2)
colnames(toy_network_ex2) <- c("source", "interaction", "target")

# Serialize the prepared objects to the specified input files
save(toy_measurements_ex2, file = "toy_measurements_ex2.RData")
save(toy_network_ex2, file = "toy_network_ex2.RData")