# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("borealis")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library("borealis")

# Identify the source directory for the example data within the borealis package
# This directory contains the bismark output files that borealis expects as input.
source_extdata_path <- system.file("extdata", "bismark", package = "borealis")

# Define the target directory in the current working directory.
# The workflow expects this directory to be named 'extdata'.
target_extdata_path <- "extdata"

# Create the target 'extdata' directory if it does not already exist.
if (!dir.exists(target_extdata_path)) {
  dir.create(target_extdata_path)
}

# Copy all files from the package's example 'extdata/bismark' directory
# to the newly created 'extdata' directory in the current working directory.
# These copied files will serve as the input for the borealis workflow.
files_to_copy <- list.files(source_extdata_path, full.names = TRUE)
file.copy(from = files_to_copy, to = target_extdata_path, overwrite = TRUE)

# The 'extdata' directory in the current working directory now contains
# the necessary input files for the borealis workflow, as specified by the vignette.