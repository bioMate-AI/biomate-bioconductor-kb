# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clustifyr")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clustifyr)

# Reproduce the VIGNETTE'S OWN data-preparation code
pbmc_matrix <- clustifyr::pbmc_matrix_small
pbmc_meta <- clustifyr::pbmc_meta
cbmc_m <- clustifyr::cbmc_m

# Serialize objects to the declared input files in .rds format,
# as readRDS is the first format attempted by the workflow's find_and_read function.
saveRDS(pbmc_matrix, "pbmc_matrix.rds")
saveRDS(pbmc_meta, "pbmc_meta.rds")
saveRDS(cbmc_m, "cbmc_m.rds")