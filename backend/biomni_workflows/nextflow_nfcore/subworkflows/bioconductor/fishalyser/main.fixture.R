library(FISHalyseR)

# 1. Copy the declared input file from the package to the working directory
f <- system.file("extdata", "SampleFISHgray.jpg", package="FISHalyseR")
if (file.exists(f)) {
    file.copy(f, "SampleFISHgray.jpg", overwrite = TRUE)
} else {
    stop("Could not find SampleFISHgray.jpg in FISHalyseR extdata")
}

# 2. Generate exImgProbes1Clean.jpg as expected by the read excerpt
img <- readImage("SampleFISHgray.jpg")
t <- calculateMaxEntropy(img)
img_probe <- img
img_probe[img_probe < t] <- 0
img_probe[img_probe >= t] <- 1
writeImage(img_probe, "exImgMaxEntropyProbes1.jpg")

img_probe_read <- readImage("exImgMaxEntropyProbes1.jpg")
anaImg_probe <- analyseParticles(img_probe_read, 20, 5, 0)
writeImage(anaImg_probe, "exImgProbes1Clean.jpg")

# 3. Generate exImgCellMaskClean.jpg as expected by the read excerpt
img_cell <- readImage("SampleFISHgray.jpg")
t2 <- calculateThreshold(img_cell)
img_cell[img_cell < t2] <- 0
img_cell[img_cell >= t2] <- 1
writeImage(img_cell, "exImgOtsuCellMask.jpg")

img_cell_read <- readImage("exImgOtsuCellMask.jpg")
anaImg_cell <- analyseParticles(img_cell_read, 20000, 1000, 0)
writeImage(anaImg_cell, "exImgCellMaskClean.jpg")