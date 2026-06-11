library(CAMERA)

# Find the mzML file shipped with CAMERA
mzml_file <- system.file('mzML/MM14.mzML', package = "CAMERA")

# Fallback to msdata if the CAMERA file is not found
if (!file.exists(mzml_file) || mzml_file == "") {
    library(msdata)
    mzmlpath <- file.path(find.package("msdata"), "microtofq")
    mzml_file <- list.files(path = mzmlpath, pattern = "^.*\\.mzML$",
                            all.files = TRUE, full.names = TRUE,
                            recursive = FALSE, ignore.case = FALSE,
                            include.dirs = FALSE, no.. = TRUE)[1]
}

# Copy the file to the working directory as expected by the workflow
file.copy(mzml_file, "file.mzML", overwrite = TRUE)