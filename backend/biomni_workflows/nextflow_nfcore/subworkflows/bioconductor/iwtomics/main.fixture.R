# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("IWTomics")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(IWTomics)

# The package provides the required example files in its extdata directory.
# We copy them to the working directory to serve as the test fixtures.
examples_path <- system.file("extdata", package="IWTomics")

# Copy all files and directories (including datasets.txt, features_datasetsTable.txt, 
# features_datasetsBED.txt, and the 'files' directory containing BED/text files)
files_to_copy <- list.files(examples_path, full.names = TRUE)
file.copy(files_to_copy, ".", recursive = TRUE, overwrite = TRUE)

# Verify the critical files exist
stopifnot(
    file.exists("datasets.txt"),
    file.exists("features_datasetsTable.txt"),
    dir.exists("files")
)