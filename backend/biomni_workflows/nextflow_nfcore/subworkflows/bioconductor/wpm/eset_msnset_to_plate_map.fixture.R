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

# [biomate-fx-dual] emit each declared input under BOTH bare-token and .rds names
# so any input-staging harness collects the real serialized object under the
# exact name the workflow reads (bare token or <token>.rds).
.bm_dual <- function(b) {
  rds <- paste0(b, '.rds')
  if (file.exists(rds) && !file.exists(b)) file.copy(rds, b, overwrite=TRUE)
  if (file.exists(b) && !file.exists(rds)) file.copy(b, rds, overwrite=TRUE)
}
.bm_dual('my_MSnSet_object')
