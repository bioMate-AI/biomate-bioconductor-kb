# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CoGAPS")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CoGAPS)

# Load the toy dataset provided by the CoGAPS package
data('modsimdata')

# Use the toy data as the counts matrix
pdac_epi_counts <- as.matrix(modsimdata)

# Create a corresponding metadata dataframe for the samples
interestedVariables <- data.frame(
    cell_id = colnames(pdac_epi_counts),
    condition = rep(c("Tumor", "Normal"), length.out = ncol(pdac_epi_counts)),
    row.names = colnames(pdac_epi_counts)
)

# Serialize the objects to the required input files
saveRDS(pdac_epi_counts, "pdac_epi_counts.rds")
saveRDS(interestedVariables, "interestedVariables.rds")