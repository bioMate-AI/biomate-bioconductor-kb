# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("RedeR", "igraph")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(RedeR)
library(igraph)

# Load the datasets shipped with the RedeR package
data("ER.limma", package = "RedeR")
data("hs.inter", package = "RedeR")

# Serialize the objects to the working directory
# Using saveRDS as the read excerpt is empty and hs.inter is a complex object (igraph)
saveRDS(ER.limma, "ER.limma")
saveRDS(hs.inter, "hs.inter")