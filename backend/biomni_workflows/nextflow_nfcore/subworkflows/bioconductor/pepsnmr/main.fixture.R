# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("PepsNMR", "PepsNMRData")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(PepsNMR)
library(PepsNMRData)

# Locate the raw Bruker NMR files shipped with the companion data package
data_path <- system.file("extdata", package = "PepsNMRData")
human_serum_dir <- file.path(data_path, "HumanSerum")

if (!dir.exists(human_serum_dir)) {
    stop("The expected 'HumanSerum' directory was not found in PepsNMRData.")
}

# Create the expected input directory
dir.create("raw_bruker_directory", showWarnings = FALSE, recursive = TRUE)

# Copy the contents (subdirectories of raw Bruker files) to the target directory
files_to_copy <- list.files(human_serum_dir, full.names = TRUE)
file.copy(from = files_to_copy, to = "raw_bruker_directory", recursive = TRUE)