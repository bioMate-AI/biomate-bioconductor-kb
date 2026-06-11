library(Cardinal)

path_continuous <- CardinalIO::exampleImzMLFile("continuous")
mse_tiny <- readMSIData(path_continuous)

# Add condition metadata as requested by the input spec
pixelData(mse_tiny)$condition <- factor(rep(c("control", "treatment"), length.out = ncol(mse_tiny)))

saveRDS(mse_tiny, "experimental_msi.rds")