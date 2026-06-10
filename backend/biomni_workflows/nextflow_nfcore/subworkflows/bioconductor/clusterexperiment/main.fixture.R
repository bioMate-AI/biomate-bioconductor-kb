# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clusterExperiment", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clusterExperiment)
library(SummarizedExperiment) # SummarizedExperiment is imported by clusterExperiment, but explicitly loading is good practice.

set.seed(14456) # For reproducibility, as in the vignette

# Reproduce the vignette's data-preparation code
# These calls load the 'fluidigmData' and 'fluidigmColData' objects into the R environment.
data(fluidigmData)
data(fluidigmColData)

# Serialize the objects to the specified input files using saveRDS
saveRDS(fluidigmData, "fluidigmData.rds")
saveRDS(fluidigmColData, "fluidigmColData.rds")