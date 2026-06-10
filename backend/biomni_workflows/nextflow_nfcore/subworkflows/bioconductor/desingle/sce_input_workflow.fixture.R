# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("DEsingle", "SingleCellExperiment")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(DEsingle)
library(SingleCellExperiment)

# Load the test data provided by the DEsingle package
data(TestData)

# Convert the 'counts' matrix to a SingleCellExperiment object
# as shown in the "With SingleCellExperiment input" section of the vignette.
sce <- SingleCellExperiment(assays = list(counts = as.matrix(counts)))

# Define the 'group' factor as specified in the vignette's usage examples.
# This redefines the 'group' object loaded by data(TestData) to explicitly match
# the example's definition.
group <- factor(c(rep(1,50), rep(2,100)))

# Serialize the SingleCellExperiment object to "sce.ext"
saveRDS(sce, "sce.ext")

# Serialize the group factor to "group.ext"
saveRDS(group, "group.ext")