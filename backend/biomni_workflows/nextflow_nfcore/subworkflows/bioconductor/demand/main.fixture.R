# Load the DeMAND package
# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DeMAND")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DeMAND)

# Load the example data from the package
# The vignette code: data(inputExample)
data(inputExample)

# The 'inputExample' dataset provides the following objects:
# bcellExp: A numeric matrix representing gene expression profiles.
# bcellAnno: A character matrix for probe annotation.
# bcellNetwork: A character matrix representing a molecular interaction network.

# The workflow's 'load_input_file' function includes 'readRDS(found_file)'
# as a method to read input files. This is a robust way to save R objects.
# We will use the '.rds' extension for the output files.

# Save bcellExp to exp.rds
saveRDS(bcellExp, file = "exp.rds")

# Save bcellAnno to anno.rds
saveRDS(bcellAnno, file = "anno.rds")

# Save bcellNetwork to network.rds
saveRDS(bcellNetwork, file = "network.rds")