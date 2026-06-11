# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("bayNorm", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(bayNorm)
library(SummarizedExperiment)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load the example data list
data('EXAMPLE_DATA_list')

# Create the rse SummarizedExperiment object
# Here we just used 30 cells for illustration
rse <- SummarizedExperiment::SummarizedExperiment(assays=SimpleList(counts=EXAMPLE_DATA_list$inputdata[,seq(1,30)]))

# Run bayNorm to generate the 3D array normalized data
# Return 3D array normalzied data, draw 20 samples from posterior distribution:
bayNorm_3D <- bayNorm(Data=rse, BETA_vec = NULL, mode_version=FALSE, mean_version = FALSE, S=20, verbose =FALSE, parallel = TRUE)

# 2. Serialize the objects to the declared input files

# Save the rse object
saveRDS(rse, "rse")

# Save the bayNorm_3D object
saveRDS(bayNorm_3D, "bayNorm_3D")