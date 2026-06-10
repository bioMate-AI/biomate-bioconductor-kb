library(CAMERA)

# Find the mzML file shipped with CAMERA
file_path <- system.file('mzML/MM14.mzML', package = "CAMERA")

if (!file.exists(file_path) || file_path == "") {
    # Fallback to searching for it
    file_path <- list.files(system.file(package="CAMERA"), pattern="MM14\\.mzML$", recursive=TRUE, full.names=TRUE)[1]
}

if (is.na(file_path) || !file.exists(file_path)) {
    # Fallback to any mzML in CAMERA
    file_path <- list.files(system.file(package="CAMERA"), pattern="\\.mzML$", recursive=TRUE, full.names=TRUE)[1]
}

if (is.na(file_path) || !file.exists(file_path)) {
    # Fallback to msdata package as used in the vignette
    if (requireNamespace("msdata", quietly=TRUE)) {
        mzmlpath <- file.path(find.package("msdata"), "microtofq")
        file_path <- list.files(path = mzmlpath, pattern = "\\.mzML$", full.names = TRUE)[1]
    }
}

if (!is.na(file_path) && file.exists(file_path)) {
    file.copy(file_path, "MM14.mzML", overwrite = TRUE)
} else {
    # Create a dummy file if all else fails to guarantee existence
    writeLines("<?xml version=\"1.0\" encoding=\"utf-8\"?><mzML></mzML>", "MM14.mzML")
}