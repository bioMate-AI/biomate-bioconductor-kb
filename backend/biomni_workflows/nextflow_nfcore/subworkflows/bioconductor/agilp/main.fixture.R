# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("agilp")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(agilp)

# Define the base path to the package's extdata directory
extdata_path <- system.file(package = "agilp", "extdata")

# 1. Create 'sample_template.txt'
# The vignette explicitly uses 'sample_template.txt' from extdata for Baseline and Loader functions.
template_source_path <- file.path(extdata_path, "sample_template.txt")
file.copy(template_source_path, "sample_template.txt", overwrite = TRUE)

# 2. Create 'annotations_sample.txt'
# The vignette explicitly uses 'annotations_sample.txt' from extdata for the IDswop function.
annotations_source_path <- file.path(extdata_path, "annotations_sample.txt")
file.copy(annotations_source_path, "annotations_sample.txt", overwrite = TRUE)

# 3. Create 'scanner_files.txt'
# The workflow expects 'scanner_files.txt' to be a single raw scanner file,
# which is then copied into 'scanner_input_dir' for AAProcess.
# The vignette's AAProcess example uses files from 'extdata/scanner/'.
# We will pick one of these example scanner files to serve as 'scanner_files.txt'.
scanner_dir_in_package <- file.path(extdata_path, "scanner")
# List files to pick one. The vignette mentions "two sample array scanner files".
# We'll take the first one found.
scanner_files_in_package <- list.files(scanner_dir_in_package, pattern = "\\.txt$", full.names = TRUE)
if (length(scanner_files_in_package) == 0) {
  stop("No scanner files found in agilp/extdata/scanner/. Cannot create scanner_files.txt.")
}
# Use the first scanner file found in the package's extdata
scanner_source_file <- scanner_files_in_package[1]
file.copy(scanner_source_file, "scanner_files.txt", overwrite = TRUE)