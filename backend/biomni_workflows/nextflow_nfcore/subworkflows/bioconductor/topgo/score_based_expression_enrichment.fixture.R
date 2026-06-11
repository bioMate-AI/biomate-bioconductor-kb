# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("topGO", "ALL")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(topGO)
library(ALL)

# Load the ALL dataset as used in the vignette
data(ALL)

# Create an integer vector of binary class labels for the samples
# Here we use B-cell vs T-cell classification from the ALL dataset
y <- as.integer(grepl("^B", ALL$BT))

# Serialize the objects to the declared input files
saveRDS(ALL, "ALL.rds")
saveRDS(y, "y.rds")