library(GeomxTools)

datadir <- system.file("extdata", "DSP_NGS_Example_Data", package="GeomxTools")

# Copy DCC files to the working directory
DCCFiles <- dir(datadir, pattern="\\.dcc$", full.names=TRUE)
file.copy(DCCFiles, ".", overwrite = TRUE)

# Unzip PKC files to the working directory
pkc_zip <- file.path(datadir, "pkcs.zip")
if (file.exists(pkc_zip)) {
    unzip(pkc_zip, exdir = ".")
}

# Copy Sample Annotation File to the working directory
SampleAnnotationFile <- file.path(datadir, "annotations.xlsx")
if (file.exists(SampleAnnotationFile)) {
    file.copy(SampleAnnotationFile, "annotations.xlsx", overwrite = TRUE)
}