# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("deconvR", "data.table")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(deconvR)
library(data.table)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# HumanCellTypeMethAtlas
data("HumanCellTypeMethAtlas")

# samples
samples <- simulateCellMix(3, reference = HumanCellTypeMethAtlas)$simulated

# sampleMeta
sampleMeta <- data.table("Experiment_accession" = colnames(samples)[-1], "Biosample_term_name" = "new cell type")

# 2. Serialize objects to declared input files in the EXACT format the workflow reads
# The workflow's read_input function prioritizes .rds files.

saveRDS(samples, "samples.rds")
saveRDS(sampleMeta, "sampleMeta.rds")
saveRDS(HumanCellTypeMethAtlas, "HumanCellTypeMethAtlas.rds")