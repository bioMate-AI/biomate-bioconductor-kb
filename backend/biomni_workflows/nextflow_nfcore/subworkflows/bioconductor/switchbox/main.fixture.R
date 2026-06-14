# [biomate] structured fixture (rule: package_example_data) — deterministic, no LLM
# switchBox ships the vignette example data set `matchedDatasets`, which provides:
#   matTraining   (genes x training-samples expression matrix)
#   trainingGroup (factor of class labels for the training samples)
#   matTesting    (genes x testing-samples expression matrix)
# The workflow's read_input() accepts either <name>.rds or <name>.csv; emit .rds (real
# serialized objects) AND the bare-token name so any input-staging harness collects them.
.fx_deps <- c("switchBox")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(switchBox)

data(matchedDatasets)

stopifnot(exists("matTraining"), exists("trainingGroup"), exists("matTesting"))

.emit <- function(obj, base) {
  rds <- paste0(base, ".rds")
  saveRDS(obj, rds)
  file.copy(rds, base, overwrite = TRUE)   # bare-token alias for staging harnesses
}

.emit(matTraining, "matTraining")
.emit(trainingGroup, "trainingGroup")
.emit(matTesting, "matTesting")
