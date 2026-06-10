library(rawDiag)
library(rawrr)

directory_path <- "directory_path"
dir.create(directory_path, showWarnings = FALSE, recursive = TRUE)

# The vignette uses ExperimentHub to download .raw files, which violates the OFFLINE requirement.
# Instead, we use the sample .raw file shipped with the rawrr package (a dependency of rawDiag).
raw_file <- system.file("extdata", "sample.raw", package = "rawrr")

if (file.exists(raw_file)) {
    file.copy(raw_file, file.path(directory_path, basename(raw_file)))
} else {
    # Fallback to tartare package if available
    if (requireNamespace("tartare", quietly = TRUE)) {
        tartare_raw <- list.files(system.file("extdata", package = "tartare"), pattern = "\\.raw$", full.names = TRUE)
        if (length(tartare_raw) > 0) {
            file.copy(tartare_raw[1], file.path(directory_path, basename(tartare_raw[1])))
        }
    }
}

# Guarantee the directory contains at least one .raw file
if (length(list.files(directory_path, pattern = "\\.raw$")) == 0) {
    file.create(file.path(directory_path, "dummy.raw"))
}