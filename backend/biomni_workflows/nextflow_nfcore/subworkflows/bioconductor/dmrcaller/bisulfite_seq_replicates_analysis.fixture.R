# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DMRcaller")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DMRcaller)

# Load the presaved data from the package
data(methylationDataList)

# Pool the methylation datasets.
# This creates a single GRanges object from the GRangesList,
# which represents the "replicates joined" concept.
methylationDataAll <- poolMethylationDatasets(methylationDataList)

# Serialize the pooled GRanges object to replicates_joined.rds
saveRDS(methylationDataAll, "replicates_joined.rds")