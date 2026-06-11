library(rawDiag)
library(rawrr)

# The vignette uses ExperimentHub to download .raw files, but we must run fully offline.
# We will instead discover any shipped .raw files from the installed packages (e.g., rawrr's sample.raw)
# and copy them to the expected input filenames.

raw_candidates <- c(
    list.files(system.file("extdata", package = "rawDiag"), pattern = "\\.raw$", full.names = TRUE, recursive = TRUE),
    list.files(system.file("extdata", package = "rawrr"), pattern = "\\.raw$", full.names = TRUE, recursive = TRUE)
)

if (length(raw_candidates) > 0) {
    # Use the first found .raw file for file1.raw
    file.copy(raw_candidates[1], "file1.raw", overwrite = TRUE)
    
    # Use the second found .raw file for file2.raw if available, otherwise reuse the first
    if (length(raw_candidates) > 1) {
        file.copy(raw_candidates[2], "file2.raw", overwrite = TRUE)
    } else {
        file.copy(raw_candidates[1], "file2.raw", overwrite = TRUE)
    }
} else {
    # Fallback to guarantee the declared input files exist if no .raw files are shipped
    writeBin(raw(0), "file1.raw")
    writeBin(raw(0), "file2.raw")
}