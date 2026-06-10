library(comapr)
library(GenomicRanges)

# Load the datasets provided by the package
data("snp_geno_gr", package = "comapr")
data("parents_geno", package = "comapr")

# Extract the progeny genotype matrix from the metadata columns of the GRanges object
progeny_df <- as.data.frame(mcols(snp_geno_gr))

# Convert parental alleles to a data frame
parents_df <- as.data.frame(parents_geno)

# Write the inputs to the expected CSV files
write.csv(progeny_df, file = "progeny_genotypes.csv", row.names = FALSE)
write.csv(parents_df, file = "parental_alleles.csv", row.names = FALSE)