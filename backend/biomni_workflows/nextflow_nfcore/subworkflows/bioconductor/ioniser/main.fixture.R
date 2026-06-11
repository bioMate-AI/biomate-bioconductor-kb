# Load required packages
library(IONiseR)
library(minionSummaryData)
library(dplyr)
library(ggplot2)
library(gridExtra)

# 1. Materialize the example objects from the vignette
data(s.typhi.rep1, package = "minionSummaryData")
data(s.typhi.rep3, package = "minionSummaryData")

# 2. Create the input directory
input_dir <- "/path/to/data"
dir.create(input_dir, recursive = TRUE, showWarnings = FALSE)

# 3. Provide .fast5 files
# Discover ready-made fast5 files shipped with IONiseR
fast5_src <- list.files(
    system.file("extdata", package = "IONiseR"), 
    pattern = "\\.fast5$", 
    recursive = TRUE, 
    full.names = TRUE
)

if (length(fast5_src) > 0) {
    # Copy existing fast5 files to the target directory
    file.copy(fast5_src, input_dir)
} else {
    # Fallback: Create a minimal dummy fast5 file using rhdf5 to satisfy the file glob
    # and prevent readFast5Summary from crashing on a completely empty/non-HDF5 file.
    dummy_file <- file.path(input_dir, "dummy.fast5")
    if (requireNamespace("rhdf5", quietly = TRUE)) {
        rhdf5::h5createFile(dummy_file)
        try({
            rhdf5::h5createGroup(dummy_file, "UniqueGlobalKey")
            rhdf5::h5createGroup(dummy_file, "UniqueGlobalKey/channel_id")
            rhdf5::h5createGroup(dummy_file, "UniqueGlobalKey/tracking_id")
            rhdf5::h5write("1", dummy_file, "UniqueGlobalKey/channel_id/channel_number")
            rhdf5::h5write("1", dummy_file, "UniqueGlobalKey/tracking_id/exp_start_time")
        }, silent = TRUE)
    } else {
        file.create(dummy_file)
    }
}

# Guarantee the declared input files exist
stopifnot(length(list.files(input_dir, pattern = "\\.fast5$")) > 0)