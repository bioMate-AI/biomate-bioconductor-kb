library(ASICS)

pure_spectra_directory <- "pure_spectra_directory"
dir.create(pure_spectra_directory, showWarnings = FALSE, recursive = TRUE)

example_lib_dir <- system.file("extdata", "example_library", package = "ASICS")

if (nzchar(example_lib_dir)) {
    files_to_copy <- list.files(example_lib_dir, full.names = TRUE)
    file.copy(files_to_copy, pure_spectra_directory, recursive = TRUE)
} else {
    stop("example_library not found in ASICS package")
}