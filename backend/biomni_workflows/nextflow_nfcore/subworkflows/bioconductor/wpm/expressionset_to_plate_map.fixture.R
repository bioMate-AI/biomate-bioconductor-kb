suppressPackageStartupMessages(library(wpm))
suppressPackageStartupMessages(library(MSnbase))

# Create a synthetic MSnSet object using the sample names and metadata from the vignette
exprs_data <- matrix(rnorm(20), ncol = 4)
colnames(exprs_data) <- c("s1", "s2", "s3", "s4")
rownames(exprs_data) <- paste0("f", 1:5)

pdata <- data.frame(
  Sample = c("s1", "s2", "s3", "s4"),
  Type = c("A", "A", "B", "C"),
  Treatment = c("trt1", "trt1", "Ctrl", "Ctrl"),
  row.names = c("s1", "s2", "s3", "s4")
)

fdata <- data.frame(
  Feature = paste0("f", 1:5),
  row.names = paste0("f", 1:5)
)

my_MSnSet_object <- new("MSnSet", 
                        exprs = exprs_data, 
                        phenoData = new("AnnotatedDataFrame", data = pdata),
                        featureData = new("AnnotatedDataFrame", data = fdata))

# Save the object to the expected files
saveRDS(my_MSnSet_object, "my_MSnSet_object")
saveRDS(my_MSnSet_object, "my_MSnSet_object.rds")