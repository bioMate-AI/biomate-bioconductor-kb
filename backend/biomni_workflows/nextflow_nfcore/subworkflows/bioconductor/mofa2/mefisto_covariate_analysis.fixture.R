# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("MOFA2", "tidyverse", "pheatmap")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(MOFA2)
library(tidyverse)
library(pheatmap)

# Reproduce the VIGNETTE'S OWN data-preparation code
set.seed(2020) # set number of samples and time points
N <- 200
time <- seq(0,1,length.out = N) # generate example data
dd <- make_example_data(sample_cov = time, n_samples = N, n_factors = 4)

# Serialize the objects to the declared input files
saveRDS(dd$data, "dd_data.rds")
saveRDS(time, "time.rds")