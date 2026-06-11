# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clustifyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clustifyr)

# Reproduce the vignette's data preparation code
# The vignette uses pbmc_matrix_small, pbmc_meta, and cbmc_ref
# These are internal datasets within the clustifyr package.
# The workflow expects 'sce', 'so', and 'cbmc_ref' files.
# Based on the clustify() function's flexibility (matrix or SCE/Seurat object for 'input')
# and the vignette's explicit use of a matrix ('pbmc_matrix') and a data.frame ('pbmc_meta'),
# we map 'pbmc_matrix' to 'sce' and 'pbmc_meta' to 'so' to satisfy the file requirements
# while strictly adhering to