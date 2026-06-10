library(Cardinal)

path_continuous <- CardinalIO::exampleImzMLFile("continuous")
mse_tiny <- readMSIData(path_continuous)

writeMSIData(mse_tiny, "aligned_peaks.imzML")