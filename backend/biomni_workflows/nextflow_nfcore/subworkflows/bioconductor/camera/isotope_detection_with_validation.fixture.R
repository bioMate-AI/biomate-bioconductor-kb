library(CAMERA)
library(xcms)
library(msdata)

mzmlpath <- file.path(find.package("msdata"), "microtofq")
if (file.exists(mzmlpath)) {
    file.copy(from = mzmlpath, to = ".", recursive = TRUE)
} else {
    stop("microtofq directory not found in msdata package.")
}