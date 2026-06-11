library(gdsfmt)
library(SNPRelate)

# Load the example dataset provided by SNPRelate
data(hapmap_geno)

# Create a GDS file as expected by the workflow
snpgdsCreateGeno("genofile.gds", 
    genmat = hapmap_geno$genotype,
    sample.id = hapmap_geno$sample.id,
    snp.id = hapmap_geno$snp.id,
    snp.chromosome = hapmap_geno$snp.chromosome,
    snp.position = hapmap_geno$snp.position,
    snp.allele = hapmap_geno$snp.allele,
    snpfirstdim = TRUE)

# Ensure the declared input file name also exists to satisfy the exact spec
file.copy("genofile.gds", "genofile")