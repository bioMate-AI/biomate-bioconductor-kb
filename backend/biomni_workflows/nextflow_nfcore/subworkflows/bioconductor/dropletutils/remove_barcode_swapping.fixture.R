library(DropletUtils)

set.seed(1000)

# Generate simulated molecule_info.h5 files for multiplexed samples
file1 <- "sample1_molecule_info.h5"
DropletUtils:::simBasicMolInfo(file1)

file2 <- "sample2_molecule_info.h5"
DropletUtils:::simBasicMolInfo(file2)

# Create the character vector of paths
mult.mol.info <- c(file1, file2)

# Serialize the character vector to the expected input file
saveRDS(mult.mol.info, "mult.mol.info")