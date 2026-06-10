# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ASSET")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ASSET)

# Locate the vdata.rda file within the ASSET package
source_datafile <- system.file("sampleData", "vdata.rda", package="ASSET")

# Define the destination filename in the current working directory
destination_datafile <- "vdata.rda"

# Copy the vdata.rda file to the current working directory
# This file contains the objects data1, data2, data3, data4 as used in the vignette.
file.copy(source_datafile, destination_datafile, overwrite = TRUE)