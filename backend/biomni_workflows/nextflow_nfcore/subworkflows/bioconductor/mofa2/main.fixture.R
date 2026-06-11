# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ggplot2", "MOFA2")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ggplot2)
library(MOFA2)

# Reproduce the model object from the vignette
filepath <- system.file("extdata", "model.hdf5", package = "MOFA2")
model <- load_model(filepath)

# Extract the 'data' object as described in the vignette
# "data" is a nested list of matrices, one matrix per view and group with dimensions (nfeatures, nsamples)
data <- get_data(model)

# Extract the 'weights' object, assuming 'dt' refers to weights based on common MOFA2 outputs
# "weights" is a list of matrices, one matrix per view with dimensions (nfeatures, nfactors)
dt <- get_weights(model, views = "all", factors = "all")

# Serialize the objects to the specified file names
saveRDS(data, "data.rds")
saveRDS(dt, "dt.rds")