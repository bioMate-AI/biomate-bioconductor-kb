# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("ASSET")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(ASSET)

# Get the path to the data file within the ASSET package
datafile_in_package <- system.file("sampleData", "vdata.rda", package="ASSET")

# Load the data frames from the package's sample data.
# This will create objects named data1, data2, data3, data4 in the environment.
load(datafile_in_package)

# Save the loaded data frames to a new vdata.rda file in the current working directory.
save(data1, data2, data3, data4, file="vdata.rda")