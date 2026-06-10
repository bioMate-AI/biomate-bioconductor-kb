# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("clusterSeq", "baySeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(clusterSeq)
library(baySeq) # baySeq is used in the vignette for cD.ratThymus creation, even if we load the pre-computed object.

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# For 'ratThymus'
data(ratThymus, package = "clusterSeq")

# For 'cD.ratThymus'
# The vignette explicitly states to load the pre-calculated object due to computation time.
data(cD.ratThymus, package = "clusterSeq")

# 2. Serialize the objects to the declared input files in the exact format the workflow reads

# Save 'ratThymus' as an RDS file
saveRDS(ratThymus, "ratThymus.rds")

# Save 'cD.ratThymus' as an RDS file
saveRDS(cD.ratThymus, "cD.ratThymus.rds")