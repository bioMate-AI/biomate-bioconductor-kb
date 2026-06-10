library(GeomxTools)

datadir <- system.file("extdata", "DSP_NGS_Example_Data", package="GeomxTools")

# Copy DCC files
dcc_files <- dir(datadir, pattern="\\.dcc$", full.names=TRUE)
file.copy(dcc_files, ".", overwrite = TRUE)

# Unzip PKC files
pkc_zip <- file.path(datadir, "pkcs.zip")
if (file.exists(pkc_zip)) {
    unzip(zipfile = pkc_zip, exdir = ".")
}

# Copy SampleAnnotationFile
anno_file <- file.path(datadir, "annotations.xlsx")
if (file.exists(anno_file)) {
    file.copy(anno_file, "annotations.xlsx", overwrite = TRUE)
    file.copy(anno_file, "SampleAnnotationFile.xlsx", overwrite = TRUE)
    file.copy(anno_file, "SampleAnnotationFile", overwrite = TRUE)
}