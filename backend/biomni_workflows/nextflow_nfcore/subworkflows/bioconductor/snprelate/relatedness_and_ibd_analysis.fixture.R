library(gdsfmt)
library(SNPRelate)

# 1. Create the GDS file 'genofile' using the package's example data
gds.fn <- snpgdsExampleFileName()
file.copy(gds.fn, "genofile", overwrite = TRUE)

# Open the GDS file to extract the required vectors
genofile_handle <- snpgdsOpen("genofile")

# 2. Extract and serialize YRI.id (Vector of sample IDs for YRI population)
samp.id <- read.gdsn(index.gdsn(genofile_handle, "sample.id"))
pop <- read.gdsn(index.gdsn(genofile_handle, "sample.annot/pop.group"))
YRI.id <- samp.id[pop == "YRI"]
saveRDS(YRI.id, "YRI.id")

# 3. Extract and serialize snpset.id (Vector of pruned SNP IDs)
set.seed(1000)
snpset <- snpgdsLDpruning(genofile_handle, ld.threshold = 0.2, autosome.only = FALSE, verbose = FALSE)
snpset.id <- unlist(unname(snpset))
saveRDS(snpset.id, "snpset.id")

# 4. Extract and serialize snp.id (Vector of selected SNP IDs)
snp.id <- read.gdsn(index.gdsn(genofile_handle, "snp.id"))
saveRDS(snp.id, "snp.id")

# 5. Extract and serialize family.id (Vector of family IDs matching the sample IDs)
family.id <- read.gdsn(index.gdsn(genofile_handle, "sample.annot/family.id"))
saveRDS(family.id, "family.id")

# Close the GDS file handle
snpgdsClose(genofile_handle)