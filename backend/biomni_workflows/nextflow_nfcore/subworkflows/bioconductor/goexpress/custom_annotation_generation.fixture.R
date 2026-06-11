# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GOexpress")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GOexpress)

# Load datasets used in the vignette
data(AlvMac)
data(AlvMac_results.pVal)
data(AlvMac_GOgenes)
data(AlvMac_allGO)
data(AlvMac_allgenes)

# Create the ensembl_host_metadata file
# Based on the vignette's biomaRt usage:
# host='feb2014.archive.ensembl.org', dataset='btaurus_gene_ensembl'
metadata <- data.frame(
    host = "feb2014.archive.ensembl.org",
    dataset = "btaurus_gene_ensembl",
    stringsAsFactors = FALSE
)

write.csv(metadata, file = "ensembl_host_metadata", row.names = FALSE)