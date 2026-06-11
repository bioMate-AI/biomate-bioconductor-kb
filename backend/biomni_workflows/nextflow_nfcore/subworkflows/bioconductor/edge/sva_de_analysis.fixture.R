# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("edge")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(edge)

# Reproduce the VIGNETTE'S OWN data-preparation code
# This code is found under the '## ----qs_load_data, cache=TRUE-----------------' chunk
data(kidney)
age <- kidney$age
sex <- kidney$sex
kidexpr <- kidney$kidexpr

# Serialize the objects to the declared input files.
# The workflow's 'load_file' function attempts to read files using 'readRDS' first.
# It also mentions trying without an extension, then as RDS.
# Therefore, saving as RDS without an explicit file extension is the most robust way
# to ensure the workflow can read these R objects.
saveRDS(kidexpr, "kidexpr")
saveRDS(sex, "sex")
saveRDS(age, "age")