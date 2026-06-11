library(gdsfmt)
library(SNPRelate)

# 1. Prepare genofile
# The vignette uses snpgdsExampleFileName() to get the example GDS file
example_gds <- snpgdsExampleFileName()

# Copy the example GDS file to the working directory as 'genofile'
file.copy(example_gds, "genofile", overwrite = TRUE)

# 2. Prepare pop_code
# Open the GDS file to extract the population group annotation as shown in the vignette
genofile_handle <- snpgdsOpen("genofile")
pop_code_data <- read.gdsn(index.gdsn(genofile_handle, path="sample.annot/pop.group"))
snpgdsClose(genofile_handle)

# Save the population codes vector to 'pop_code'
saveRDS(pop_code_data, "pop_code")