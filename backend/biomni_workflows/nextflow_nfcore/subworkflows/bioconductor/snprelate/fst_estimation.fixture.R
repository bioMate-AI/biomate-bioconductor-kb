library(gdsfmt)
library(SNPRelate)

# Get the example GDS file shipped with SNPRelate
gds_path <- snpgdsExampleFileName()

# The workflow expects a file named 'genofile' in the working directory
file.copy(gds_path, "genofile", overwrite = TRUE)

# Open the GDS file to extract the required vectors
genofile_handle <- snpgdsOpen(gds_path)

# Extract sample IDs and population codes as per the vignette's structure
samp.sel <- read.gdsn(index.gdsn(genofile_handle, "sample.id"))
pop.sel <- read.gdsn(index.gdsn(genofile_handle, "sample.annot/pop.group"))

# Close the file handle
snpgdsClose(genofile_handle)

# Serialize the vectors to the working directory
saveRDS(samp.sel, "samp.sel")
saveRDS(pop.sel, "pop.sel")