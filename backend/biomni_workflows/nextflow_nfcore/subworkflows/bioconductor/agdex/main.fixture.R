# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AGDEX")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AGDEX)

# Load the data objects as shown in the vignette
data(human.data)
data(mouse.data)
data(gset.data)
data(map.data)

# Save each object to its corresponding input file using saveRDS
# The workflow's read_input function tries readRDS first.
saveRDS(human.data, "human.data")
saveRDS(mouse.data, "mouse.data")
saveRDS(gset.data, "gset.data")
saveRDS(map.data, "map.data")