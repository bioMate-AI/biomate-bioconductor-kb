library(cliqueMS)
library(xcms)

# Locate the mzXML file shipped with the package as per the vignette
mzfile <- system.file("standards.mzXML", package = "cliqueMS")

# Fallback searches if the exact path has changed in the installed version
if (mzfile == "" || !file.exists(mzfile)) {
    mzfiles <- list.files(system.file(package = "cliqueMS"), pattern = "standards\\.mzXML$", recursive = TRUE, full.names = TRUE)
    if (length(mzfiles) > 0) {
        mzfile <- mzfiles[1]
    } else {
        mzfiles <- list.files(system.file(package = "cliqueMS"), pattern = "\\.mzXML$", recursive = TRUE, full.names = TRUE)
        if (length(mzfiles) > 0) {
            mzfile <- mzfiles[1]
        }
    }
}

# Copy the file to the working directory to satisfy the workflow's expected input
if (file.exists(mzfile)) {
    file.copy(mzfile, "standards.mzXML", overwrite = TRUE)
} else {
    # Ultimate fallback to msdata companion package if cliqueMS no longer ships it
    if (requireNamespace("msdata", quietly = TRUE)) {
        mzfiles <- list.files(system.file(package = "msdata"), pattern = "\\.mzXML$", recursive = TRUE, full.names = TRUE)
        if (length(mzfiles) > 0) {
            file.copy(mzfiles[1], "standards.mzXML", overwrite = TRUE)
        }
    }
}