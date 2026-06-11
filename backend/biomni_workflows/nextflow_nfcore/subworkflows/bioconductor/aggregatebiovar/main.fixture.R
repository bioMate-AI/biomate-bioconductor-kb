# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("aggregateBioVar", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(aggregateBioVar)
library(SingleCellExperiment) # small_airway is a SingleCellExperiment object

# Reproduce the vignette's data-preparation code
# The vignette states "A subset of ... cells ... are available in the small_airway data set."
# This implies it's an exported dataset within the package.
data(small_airway)

# Serialize the object to the declared input file in the exact format the workflow reads
saveRDS(small_airway, file = "small_airway.rds")