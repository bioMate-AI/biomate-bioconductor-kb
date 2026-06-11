# [biomate-fx-name] write targets matched to the workflow's declared input filenames
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("banocc")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(banocc)

# Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette loads 'compositions_null' using data()
data(compositions_null)

# Serialize the 'compositions_null' object to the input file "compositions_null"
# The workflow reads this file using read.csv("compositions_null", header = TRUE, check.names = FALSE)
# To match this, we save the data frame as a CSV, ensuring no row names are written
# and that the header is included (which is the default for write.csv).
write.csv(compositions_null, file = "compositions_null.csv", row.names = FALSE)