library(EBImage)

# Find and copy shapes.png
shapes_candidates <- list.files(system.file(package="EBImage"), pattern="shapes\\.png$", recursive=TRUE, full.names=TRUE)
if (length(shapes_candidates) > 0) {
    file.copy(shapes_candidates[1], "shapes.png", overwrite = TRUE)
} else {
    # Fallback to guarantee file exists
    shapes <- Image(matrix(0, 100, 100))
    shapes[25:75, 25:75] <- 1
    writeImage(shapes, "shapes.png")
}

# Find and copy nuclei.tif
nuclei_candidates <- list.files(system.file(package="EBImage"), pattern="nuclei\\.tif$", recursive=TRUE, full.names=TRUE)
if (length(nuclei_candidates) > 0) {
    file.copy(nuclei_candidates[1], "nuclei.tif", overwrite = TRUE)
} else {
    # Fallback to guarantee file exists
    nuc <- Image(array(0, dim = c(100, 100, 4)))
    writeImage(nuc, "nuclei.tif")
}