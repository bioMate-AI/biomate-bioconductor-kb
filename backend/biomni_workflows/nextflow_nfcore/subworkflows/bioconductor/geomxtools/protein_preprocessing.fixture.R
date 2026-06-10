library(GeomxTools)

# Locate the example data directory provided by GeomxTools
datadir <- system.file("extdata", "DSP_NGS_Example_Data", package="GeomxTools")

# 1. DCCFiles (DCC expression files)
DCCFiles <- dir(datadir, pattern="\\.dcc$", full.names=TRUE)
file.copy(DCCFiles, ".", overwrite = TRUE)

# 2. PKCFiles (PKC protein kit configuration files)
pkc_zip <- file.path(datadir, "pkcs.zip")
if (file.exists(pkc_zip)) {
    unzip(zipfile = pkc_zip, exdir = ".")
}

# 3. SampleAnnotationFile (Excel spreadsheet containing sample annotations)
SampleAnnotationFile <- file.path(datadir, "annotations.xlsx")
if (file.exists(SampleAnnotationFile)) {
    file.copy(SampleAnnotationFile, basename(SampleAnnotationFile), overwrite = TRUE)
}