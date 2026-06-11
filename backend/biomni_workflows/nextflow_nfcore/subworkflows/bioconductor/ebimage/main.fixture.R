library(EBImage)

nuc_files <- list.files(system.file(package="EBImage"), pattern="nuclei\\.tif$", recursive=TRUE, full.names=TRUE)
if (length(nuc_files) > 0) {
    file.copy(nuc_files[1], "nuclei.tif", overwrite=TRUE)
}

cel_files <- list.files(system.file(package="EBImage"), pattern="cells\\.tif$", recursive=TRUE, full.names=TRUE)
if (length(cel_files) > 0) {
    file.copy(cel_files[1], "cells.tif", overwrite=TRUE)
}

if (!file.exists("nuclei.tif")) {
    nuc <- Image(matrix(0, 10, 10))
    writeImage(nuc, "nuclei.tif")
}

if (!file.exists("cells.tif")) {
    cel <- Image(matrix(0, 10, 10))
    writeImage(cel, "cells.tif")
}