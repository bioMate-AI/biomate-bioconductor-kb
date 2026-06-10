# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("matter")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(matter)

# Set seed for reproducibility as in the vignette
set.seed(1)

# Create a native R array with enough elements to satisfy the 'n' argument in readBin.
# The workflow tries to read at least 120 elements.
# We'll create an array with 150 double elements, which is more than 120.
# The vignette uses `array(sort(runif(24)), dim=c(4,3,2))` for `a1`.
# We adapt this to generate a larger dataset.
num_elements <- 150
a1 <- array(sort(runif(num_elements)), dim=c(10, 5, 3)) # 10 * 5 * 3 = 150 elements

# Create a matter_arr object from the native R array.
# This function writes the data to a temporary binary file.
a2 <- matter_arr(a1)

# Get the path to the temporary file created by matter_arr
temp_file_path <- path(a2)

# Copy the content of the temporary file to "raw_data.bin" in the working directory.
# This file will contain the raw double data, matching the primary 'what = "double"'
# read operation in the workflow.
file.copy(temp_file_path, "raw_data.bin", overwrite = TRUE)

# Clean up the temporary file created by matter_arr.
file.remove(temp_file_path)

# The 'raw_data.bin' file now contains 150 double-precision floating-point numbers.
# When the workflow reads it:
# - If 'file_size' is correctly determined (150 * 8 = 1200 bytes),
# - 'n' will be max(120, 1200 / 8) = max(120, 150) = 150.
# - The primary readBin("raw_data.bin", what = "double", n = 150) will successfully
#   read all 150 doubles, and the fallback to integer will not be triggered.