library(DiffBind)

# The vignette uses the 'tamoxifen.csv' and associated peak/bam files 
# shipped in the 'extra' directory of the DiffBind package.
extra_dir <- system.file("extra", package = "DiffBind")

# Copy all files and subdirectories (including tamoxifen.csv and BED/Peak files)
# to the current working directory so they can be read directly by the workflow.
files_to_copy <- list.files(extra_dir, full.names = TRUE)
file.copy(files_to_copy, ".", recursive = TRUE, overwrite = TRUE)

# Verify the main input file exists
if (!file.exists("tamoxifen.csv")) {
    stop("Failed to copy tamoxifen.csv to the working directory.")
}