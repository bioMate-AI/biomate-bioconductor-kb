# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AffiXcan", "MultiAssayExperiment", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(AffiXcan)
library(MultiAssayExperiment)
library(SummarizedExperiment)

# 1. Reproduce training.tba.toydata.rds
# From vignette section 3.1.1 "TBA matrices"
tba_obj <- readRDS(system.file("extdata", "training.tba.toydata.rds", package="AffiXcan"))
saveRDS(tba_obj, "training.tba.toydata.rds")

# 2. Reproduce exprMatrix
# From vignette section 3.1.2 "Expression matrix" and 3.3 "Final Output"
data(exprMatrix, package="AffiXcan")
saveRDS(exprMatrix, "exprMatrix")

# 3. Reproduce regionAssoc
# From vignette section 3.1.3 "Gene - Region(s) associations" and 3.3 "Final Output"
data(regionAssoc, package="AffiXcan")
saveRDS(regionAssoc, "regionAssoc")

# 4. Reproduce trainingCovariates
# From vignette section 3.1.4 "Pupulation structure covariates" and 3.3 "Final Output"
data(trainingCovariates, package="AffiXcan")
saveRDS(trainingCovariates, "trainingCovariates")