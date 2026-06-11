library("SDAMS")

set.seed(100)
featureInfo_mat <- matrix(runif(8000, -2, 5), ncol = 40)
featureInfo_mat[featureInfo_mat < 0] <- 0
rownames(featureInfo_mat) <- paste("gene", 1:200, sep = '')
colnames(featureInfo_mat) <- paste('cell', 1:40, sep = '')

groupInfo_df <- data.frame(grouping = matrix(sample(0:1, 40, replace = TRUE), ncol = 1))
rownames(groupInfo_df) <- colnames(featureInfo_mat)

write.csv(featureInfo_mat, file = "featureInfo", row.names = TRUE)
write.csv(groupInfo_df, file = "groupInfo", row.names = TRUE)