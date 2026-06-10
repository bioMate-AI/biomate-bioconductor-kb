# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("alevinQC")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(alevinQC)

# 1. Reproduce the VIGNETTE'S OWN data-preparation code.
# The alevinQC vignette uses `system.file` to point to a pre-existing
# example alevin output directory structure within the package.
# This structure contains all the necessary input files for the workflow.
source_baseDir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")

# 2. Serialize that object (the collection of input files) to the
#    declared input directory (`baseDir`) in the working directory.
#    The workflow expects to read these files from a directory named "baseDir"
#    in the current working directory.
target_baseDir <- "baseDir"

# Ensure a clean slate by removing any pre-existing target directory
if (dir.exists(target_baseDir)) {
  unlink(target_baseDir, recursive = TRUE)
}

# Create the target directory where the workflow will look for inputs
dir.create(target_baseDir, recursive = TRUE)

# Copy the entire contents (files and subdirectories) from the
# vignette's example data path to the newly created target_baseDir.
# This replicates the exact file structure and content that `readAlevinQC` expects.
# `list.files(source_baseDir, full.names = TRUE)` gets the full paths of
# all items (files and subdirectories) directly within source_baseDir.
# `file.copy(..., to = target_baseDir, recursive = TRUE)` copies these items
# into target_baseDir, preserving their internal structure.
file.copy(
  from = list.files(source_baseDir, full.names = TRUE),
  to = target_baseDir,
  recursive = TRUE
)

# At this point, the current working directory contains a 'baseDir'
# directory with the exact structure and files required by the alevinQC workflow,
# as demonstrated in the package vignette.
# For example, it will contain 'baseDir/alevin/', 'baseDir/aux_info/', and 'baseDir/cmd_info.json'.