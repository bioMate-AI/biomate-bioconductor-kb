# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ClusterSignificance")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ClusterSignificance)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette explicitly loads mlpMatrix using data()
data(mlpMatrix)

# The vignette then creates the 'classes' variable from the rownames of mlpMatrix
classes_vector <- rownames(mlpMatrix)

# 2. Serialize the objects to the declared input files in the EXACT format the workflow reads
# The workflow's helper functions prioritize readRDS, which is suitable for R objects.
saveRDS(mlpMatrix, file = "mlpMatrix")
saveRDS(classes_vector, file = "classes")