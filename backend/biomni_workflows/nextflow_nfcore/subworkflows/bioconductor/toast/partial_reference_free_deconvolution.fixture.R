# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TOAST")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TOAST)

# Reproduce the vignette's data-preparation code
data("CBS_PBMC_array")

# Materialize the objects the analysis consumes
CBS_mix <- CBS_PBMC_array$mixed_all
LM_5 <- CBS_PBMC_array$LM_5

# The workflow reads 'CellType'. From the vignette, LM_5 is a reference matrix
# for immune cell types, and its column names represent these cell types.
CellType <- colnames(LM_5)

# Serialize objects to the exact file names and format the workflow reads
saveRDS(CBS_mix, "CBS_mix.rds")
saveRDS(LM_5, "LM_5.rds")
saveRDS(CellType, "CellType.rds")