# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CellMixS", "SingleCellExperiment", "cowplot", "limma", "magrittr", "dplyr", "purrr", "ggplot2", "scater")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CellMixS)
library(SingleCellExperiment)
library(cowplot)
library(limma)
library(magrittr)
library(dplyr)
library(purrr)
library(ggplot2)
library(scater)

# Load sim_list example data
sim_list <- readRDS(system.file(file.path("extdata", "sim50.rds"), package = "CellMixS"))
sce50 <- sim_list[["batch50"]]

# Serialize the object to the expected input file
saveRDS(sce50, "sce50.rds")