library(CAMERA)
library(msdata)
library(xcms)

# Create the required input directory
dir.create("cdf", showWarnings = FALSE, recursive = TRUE)

# 1. Copy CDF files from the msdata package
cdf_dir <- system.file("cdf", package = "msdata")
if (nzchar(cdf_dir)) {
    cdf_files <- list.files(cdf_dir, full.names = TRUE, recursive = TRUE, pattern = "\\.CDF$|\\.cdf$")
    file.copy(cdf_files, "cdf/")
}

# 2. Copy the mzML file from the CAMERA package (used in the vignette)
camera_mzml <- system.file("mzML/MM14.mzML", package = "CAMERA")
if (file.exists(camera_mzml)) {
    file.copy(camera_mzml, "cdf/")
}

# 3. Copy the microtofq mzML files from the msdata package (used in the vignette)
msdata_mzml_dir <- file.path(find.package("msdata"), "microtofq")
if (file.exists(msdata_mzml_dir)) {
    msdata_mzml <- list.files(path = msdata_mzml_dir, pattern = "\\.mzML$", full.names = TRUE)
    file.copy(msdata_mzml, "cdf/")
}