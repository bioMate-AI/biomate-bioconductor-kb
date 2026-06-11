library(LEA)

data("offset_example", package = "LEA")
Y <- offset_example$geno
X <- offset_example$env
X.pred <- offset_example$env.pred

saveRDS(Y, "Y.rds")
saveRDS(X, "X.rds")
saveRDS(X.pred, "X.pred.rds")