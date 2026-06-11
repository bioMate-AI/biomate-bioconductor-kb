library(Cardinal)

path_continuous <- CardinalIO::exampleImzMLFile("continuous")
mse_tiny <- readMSIData(path_continuous)

# Add a dummy pixel class label in case the workflow expects it
pixelData(mse_tiny)$class <- factor(sample(c("A", "B"), ncol(mse_tiny), replace = TRUE))

writeMSIData(mse_tiny, "aligned_peaks.imzML")