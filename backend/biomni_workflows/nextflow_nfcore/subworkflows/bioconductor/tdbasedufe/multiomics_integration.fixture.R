# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("TDbasedUFE", "MOFAdata")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(TDbasedUFE)
library(MOFAdata)

# Load the multiomics dataset and covariates from MOFAdata as used in the vignette
data("CLL_data")
data("CLL_covariates")

# Serialize the multiomics list of matrices to the expected RDS file
saveRDS(CLL_data, "multiomics_list.rds")

# Serialize the clinical covariates to the expected CSV file
write.csv(CLL_covariates, "clinical_covariates.csv", row.names = TRUE)