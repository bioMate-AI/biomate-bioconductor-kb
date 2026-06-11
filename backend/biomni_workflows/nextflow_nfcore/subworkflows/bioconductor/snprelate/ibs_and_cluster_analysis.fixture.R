library(gdsfmt)
library(SNPRelate)

# The workflow expects a GDS file. 
# Note: An opened GDS file object contains external C pointers and cannot be 
# serialized/deserialized via saveRDS(). Therefore, we provide the actual 
# binary GDS file at the expected path so it can be opened via snpgdsOpen().
gds_file <- snpgdsExampleFileName()
file.copy(gds_file, "genofile", overwrite = TRUE)