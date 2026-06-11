# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("BEAT")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(BEAT)

# Get the path to the package's example data
localpath_extdata <- system.file('extdata', package = 'BEAT')

# Define the names of the input files as expected by the workflow
reference_file_name <- "reference.positions.csv"
sample_file_name <- "sample.positions.csv"

# Construct full paths to the example data files within the package
reference_path_in_package <- file.path(localpath_extdata, reference_file_name)
sample_path_in_package <- file.path(localpath_extdata, sample_file_name)

# Read the example data from the package
reference_positions <- read.csv(reference_path_in_package)
sample_positions <- read.csv(sample_path_in_package)

# Write these data frames to the current working directory
# The workflow expects these files to be in the working directory.
# Ensure format matches read.csv: default separator is comma, no row names.
write.csv(reference_positions, reference_file_name, row.names = FALSE)
write.csv(sample_positions, sample_file_name, row.names = FALSE)