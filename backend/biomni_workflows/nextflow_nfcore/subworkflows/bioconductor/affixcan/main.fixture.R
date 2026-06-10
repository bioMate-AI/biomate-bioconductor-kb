# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("AffiXcan", "MultiAssayExperiment", "SummarizedExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
suppressMessages(library(AffiXcan))
suppressMessages(library(MultiAssayExperiment))
suppressMessages(library(SummarizedExperiment))

# 1. Reproduce the VIGNETTE'S OWN data-preparation code

# training.tba.toydata.rds
# Vignette code: tba <- readRDS(system.file("extdata","training.tba.toydata.rds", package="AffiXcan"))
training_tba_toydata_rds_obj <- readRDS(system.file("extdata","training.tba.toydata.rds", package="AffiXcan"))

# exprMatrix
# Vignette code: data(exprMatrix)
data(exprMatrix, package="AffiXcan")

# regionAssoc
# Vignette code: data(regionAssoc)
data(regionAssoc, package="AffiXcan")

# trainingCovariates
# Vignette code: data(trainingCovariates)
data(trainingCovariates, package="AffiXcan")

# testing.tba.toydata.rds
# Vignette code: testingTbaPaths <- system.file("extdata","testing.tba.toydata.rds", package="AffiXcan")
testing_tba_toydata_rds_obj <- readRDS(system.file("extdata","testing.tba.toydata.rds", package="AffiXcan"))

# 2. Serialize objects to EACH declared input file in the exact format the workflow reads

# The workflow's `read_input` function attempts to read files as RDS first.
# Therefore, saving all R objects as RDS files is the most robust approach.
saveRDS(exprMatrix, "exprMatrix")
saveRDS(training_tba_toydata_rds_obj, "training.tba.toydata.rds")
saveRDS(regionAssoc, "regionAssoc")
saveRDS(trainingCovariates, "trainingCovariates")
saveRDS(testing_tba_toydata_rds_obj, "testing.tba.toydata.rds")