# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("Linnorm")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(Linnorm)

# Obtain data as shown in the vignette
data(LIHC, package="Linnorm")
data(Islam2011, package="Linnorm")

# Prepare IslamData as in the vignette
IslamData <- Islam2011[, 1:92]

# Serialize objects to the declared input files
# (Using saveRDS as the read excerpt is empty and these are matrix objects)
saveRDS(LIHC, "LIHC")
saveRDS(IslamData, "IslamData")