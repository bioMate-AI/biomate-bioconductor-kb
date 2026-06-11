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
# pbmc_matrix is derived from clustifyr::pbmc_matrix_small
pbmc_matrix_obj <- clustifyr::pbmc_matrix_small

# pbmc_meta is derived from clustifyr::pbmc_meta
pbmc_meta_obj <- clustifyr::pbmc_meta

# cbmc_ref is derived from clustifyr::cbmc_ref
cbmc_ref_obj <- clustifyr::cbmc_ref

# Serialize objects to the declared input files in .rds format
saveRDS(pbmc_matrix_obj, "pbmc_matrix.rds")
saveRDS(pbmc_meta_obj, "pbmc_meta.rds")
saveRDS(cbmc_ref_obj, "cbmc_ref.rds")