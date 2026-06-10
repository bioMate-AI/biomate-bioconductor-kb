# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("crlmm", "VanillaICE")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(crlmm)
library(VanillaICE) # As VanillaICE is the canonical package for the workflow

# Reproduce the data-preparation code from the vignette
# This loads the 'cnSetExample' object into the R environment.
data(cnSetExample, package="crlmm")

# Serialize the 'cnSetExample' object to the input file expected by the workflow.
# The workflow checks for "cnSetExample" first, then "cnSetExample.rds".
# Saving it without an extension matches the first check.
saveRDS(cnSetExample, "cnSetExample.rds")