# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("miloR", "SingleCellExperiment", "scater", "scran", "dplyr", "patchwork")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(miloR)
library(SingleCellExperiment)
library(scater)
library(scran)
library(dplyr)
library(patchwork)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
#    The workflow reads 'pbmc.sce' and 'pbmc.design'.
#    The vignette's primary differential abundance analysis uses 'traj_sce' and 'traj_design'.
#    We will generate these objects and save them under the requested filenames.

# Load data from miloR package
data("sim_trajectory", package = "miloR")

# Extract SingleCellExperiment object and metadata
traj_sce <- sim_trajectory[['SCE']]
traj_meta <- sim_trajectory