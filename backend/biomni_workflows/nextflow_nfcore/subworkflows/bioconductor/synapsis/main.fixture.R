library(synapsis)
library(EBImage)

path <- system.file("extdata", package = "synapsis")

# Find the MLH3 (foci) channel image
mlh3_files <- list.files(path, pattern = "MLH3.*\\.tif$", full.names = TRUE, recursive = TRUE)
if (length(mlh3_files) > 0) {
    file.copy(mlh3_files[1], "foci_channel.tif", overwrite = TRUE)
} else {
    # Fallback: create a synthetic image if the package data is missing
    img_foci <- Image(matrix(runif(750 * 750), 750, 750))
    writeImage(img_foci, "foci_channel.tif")
}

# Find the SYCP3 (synaptonemal complex) channel image
sycp3_files <- list.files(path, pattern = "SYCP3.*\\.tif$", full.names = TRUE, recursive = TRUE)
if (length(sycp3_files) > 0) {
    file.copy(sycp3_files[1], "sc_channel.tif", overwrite = TRUE)
} else {
    # Fallback: create a synthetic image if the package data is missing
    img_sc <- Image(matrix(runif(750 * 750), 750, 750))
    writeImage(img_sc, "sc_channel.tif")
}