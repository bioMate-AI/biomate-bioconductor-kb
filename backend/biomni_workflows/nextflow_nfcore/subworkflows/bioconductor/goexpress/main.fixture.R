# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("GOexpress")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(GOexpress)

# Load the ExpressionSet dataset from the package
data("AlvMac", package = "GOexpress")

# Save the ExpressionSet to the expected input file
save(AlvMac, file = "user_expression_data.RData")

# Load the custom annotation datasets from the package
data("AlvMac_GOgenes", package = "GOexpress")
data("AlvMac_allGO", package = "GOexpress")
data("AlvMac_allgenes", package = "GOexpress")

# Save the annotation data frames to the expected input file
save(AlvMac_GOgenes, AlvMac_allGO, AlvMac_allgenes, file = "custom_annotations.RData")