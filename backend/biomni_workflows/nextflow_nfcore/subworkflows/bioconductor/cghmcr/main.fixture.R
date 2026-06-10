# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("CNTools", "cghMCR")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(CNTools)
library(cghMCR) # Load the main package as requested

# Reproduce the vignette's data-preparation code to materialize the example objects.
# The vignette explicitly loads 'sampleData' and 'geneInfo' datasets.
# From vignette chunk 8:
data("sampleData", package = "CNTools")

# From vignette chunk 9:
data(geneInfo) # This loads the 'geneInfo' dataset, which is also from CNTools.

# Serialize the objects to the declared input files ("sampleData", "geneInfo").
# The workflow's `read_input_file` helper function snippet shows that
# `read.csv` is the first and only effective read attempt if the file exists
# (due to the structure of the `return` statements).
# Therefore, the output files must be in CSV format.
# `row.names = FALSE` is used to prevent writing an extra column for R's row names,
# which is typically not part of the original data.

write.csv(sampleData, "sampleData", row.names = FALSE)
write.csv(geneInfo, "geneInfo", row.names = FALSE)