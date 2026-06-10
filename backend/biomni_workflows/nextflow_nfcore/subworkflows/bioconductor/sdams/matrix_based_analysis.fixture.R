library("SDAMS")

set.seed(100)
featureInfo <- matrix(runif(8000, -2, 5), ncol = 40)
featureInfo[featureInfo < 0] <- 0
rownames(featureInfo) <- paste("gene", 1:200, sep = '')
colnames(featureInfo) <- paste('cell', 1:40, sep = '')

groupInfo <- data.frame(grouping = matrix(sample(0:1, 40, replace = TRUE), ncol = 1))
rownames(groupInfo) <- colnames(featureInfo)

saveRDS(featureInfo, "featureInfo")
saveRDS(groupInfo, "groupInfo")