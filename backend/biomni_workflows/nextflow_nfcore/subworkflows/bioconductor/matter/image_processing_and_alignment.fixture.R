# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("matter")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(matter)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
# This section creates a native R matrix 'm1' as shown in section 3.2.2
# "Column-major and row-major matrices" of the vignette.
set.seed(1)
m1 <- matrix(sort(runif(35)), nrow=5, ncol=7)

# Define a persistent path for the binary data file that will store the matrix data.
# matter objects are out-of-memory, meaning the actual data resides in a separate file.
# The .rds file will contain a matter_mat object that references this binary data file.
data_file_path <- "image_matrix_data.bin