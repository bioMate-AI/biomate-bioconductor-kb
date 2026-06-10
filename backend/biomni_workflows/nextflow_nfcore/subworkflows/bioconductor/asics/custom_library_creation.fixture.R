library(ASICS)

src_dir <- system.file("extdata", "example_library", package = "ASICS")
if (nzchar(src_dir) && file.exists(src_dir)) {
    file.copy(src_dir, ".", recursive = TRUE)
} else {
    stop("Could not find example_library in ASICS package")
}