# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("EDASeq", "yeastRNASeq")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(EDASeq)
library(yeastRNASeq)

# Load the datasets as demonstrated in the vignette
data(geneLevelData, package = "yeastRNASeq")
data(yeastGC, package = "EDASeq")
data(yeastLength, package = "EDASeq")

# Serialize the objects to the working directory as expected by the workflow
saveRDS(geneLevelData, "geneLevelData")
saveRDS(yeastGC, "yeastGC")
saveRDS(yeastLength, "yeastLength")