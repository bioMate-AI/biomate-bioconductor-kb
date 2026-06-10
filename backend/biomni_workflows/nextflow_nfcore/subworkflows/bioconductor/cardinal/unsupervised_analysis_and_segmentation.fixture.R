library(Cardinal)
library(CardinalIO)

path_continuous <- CardinalIO::exampleImzMLFile("continuous")
mse_tiny <- readMSIData(path_continuous)

saveRDS(mse_tiny, "processed_msi.rds")