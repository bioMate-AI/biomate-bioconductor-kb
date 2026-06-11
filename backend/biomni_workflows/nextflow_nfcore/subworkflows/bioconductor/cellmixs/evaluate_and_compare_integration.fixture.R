# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CellMixS", "SingleCellExperiment", "magrittr", "dplyr", "purrr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CellMixS)
library(SingleCellExperiment)
library(magrittr) # For %>%
library(dplyr)    # For bind_cols (used in vignette, good to include)
library(purrr)    # For map (used in vignette, good to include)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# Load sim_list example data
sim_list_original <- readRDS(system.file(file.path("extdata", "sim50.rds"), package = "CellMixS"))

# Extract sce50 and apply cms
sce50_processed <- sim_list_original[["batch50"]]
sce50_processed <- cms(sce50_processed, k = 30, group = "batch", res_name = "unaligned", n_dim = 3, cell_min = 4)

# Define batch_names for the lapply call
batch_names <- c("batch0", "batch20")

# Apply cms to batch0 and batch20 from the original sim_list
sim_list_processed_subset <- lapply(batch_names, function(name){
  sce <- sim_list_original[[name]]
  sce <- cms(sce, k = 30, group = "batch", res_name = "unaligned", n_dim = 3, cell_min = 4)
  return(sce)
}) %>% set_names(batch_names)

# Reconstruct the final sim_list (which will be sce_pre_list)
# This list will contain processed "batch0", "batch20", and "batch50"
sce_pre_list <- sim_list_processed_subset
sce_pre_list[["batch5