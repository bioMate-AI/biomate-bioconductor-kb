library(Cardinal)
library(CardinalIO)

path_continuous <- CardinalIO::exampleImzMLFile("continuous")
mse_tiny <- readMSIData(path_continuous)

# Add class labels to pixel metadata
mse_tiny$class <- factor(rep(c("Group1", "Group2"), length.out = ncol(mse_tiny)))

saveRDS(mse_tiny, "labeled_msi.rds")