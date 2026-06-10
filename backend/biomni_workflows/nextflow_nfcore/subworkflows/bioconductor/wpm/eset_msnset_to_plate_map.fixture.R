library(wpm)
library(MSnbase)

# Recreate the example dataset from the vignette
exprs_mat <- matrix(rnorm(16), nrow = 4, ncol = 4)
colnames(exprs_mat) <- c("s1", "s2", "s3", "s4")
rownames(exprs_mat) <- paste0("f", 1:4)

pdata_df <- data.frame(
    Sample = c("s1", "s2", "s3", "s4"),
    Type = c("A", "A", "B", "C"),
    Treatment = c("trt1", "trt1", "Ctrl", "Ctrl"),
    row.names = c("s1", "s2", "s3", "s4")
)

my_MSnSet_object <- MSnSet(exprs = exprs_mat, pData = pdata_df)

# Serialize the object to the declared input file
saveRDS(my_MSnSet_object, "my_MSnSet_object")