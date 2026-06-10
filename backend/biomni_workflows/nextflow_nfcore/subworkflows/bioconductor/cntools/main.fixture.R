# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNTools")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("CNTools")

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# The vignette loads 'sampleData' and 'geneInfo' directly from the package.

# Load the sampleData object
data(sampleData)

# Load the geneInfo object
data(geneInfo)

# 2. Serialize the objects to the declared input files
# The workflow reads files named "sampleData" and "geneInfo" from the working directory.
# The workflow's 'find_and_read' function attempts to read using read.csv, read.delim,
# or read.table, all with header = TRUE, stringsAsFactors = FALSE.
# Saving as a CSV file without row names is the most compatible approach.

# Save sampleData to a file named "sampleData"
write.csv(sampleData, file = "sampleData", row.names = FALSE)

# Save geneInfo to a file named "geneInfo"
write.csv(geneInfo, file = "geneInfo", row.names = FALSE)