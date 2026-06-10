# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BOBaFIT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BOBaFIT)

# Load the dataset provided by the package as described in the vignette
data("TCGA_BRCA_CN_segments", package = "BOBaFIT")

# Write the dataset to the expected input file 'data.txt' as a tab-separated file
write.table(
  TCGA_BRCA_CN_segments, 
  file = "data.txt", 
  sep = "\t", 
  quote = FALSE, 
  row.names = FALSE
)