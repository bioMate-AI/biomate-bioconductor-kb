library(PanomiR)
data("miniTestsPanomiR", package = "PanomiR")

write.csv(miniTestsPanomiR$mini_LIHC_Exp, file = "gene_expression.csv", row.names = TRUE)
write.csv(miniTestsPanomiR$mini_LIHC_Cov, file = "covariates.csv", row.names = TRUE)