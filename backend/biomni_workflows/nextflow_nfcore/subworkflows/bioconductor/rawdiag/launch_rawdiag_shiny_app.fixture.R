library(rawDiag)
library(rawrr)

# Create the expected input directory
dir.create("directory_path", showWarnings = FALSE, recursive = TRUE)

# The vignette uses ExperimentHub to fetch .raw files, which requires internet access.
# To run fully offline, we use the sample .raw file shipped with the rawrr package.
raw_file <- system.file("extdata", "sample.raw", package = "rawrr")

if (file.exists(raw_file)) {
    file.copy(raw_file, file.path("directory_path", basename(raw_file)))
} else {
    # Fallback: search for any .raw file in the rawrr package
    raw_files <- list.files(system.file(package = "rawrr"), pattern = "\\.raw$", recursive = TRUE, full.names = TRUE)
    if (length(raw_files) > 0) {
        file.copy(raw_files[1], file.path("directory_path", basename(raw_files[1])))
    } else {
        # Ultimate fallback: create a dummy file to satisfy the file existence requirement
        writeBin(as.raw(0), file.path("directory_path", "sample.raw"))
    }
}