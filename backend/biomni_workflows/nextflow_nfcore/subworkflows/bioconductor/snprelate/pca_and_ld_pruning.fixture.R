library(gdsfmt)
library(SNPRelate)

data(hapmap_geno)

snpgdsCreateGeno("genofile", 
    genmat = hapmap_geno$genotype,
    sample.id = hapmap_geno$sample.id,
    snp.id = hapmap_geno$snp.id,
    snp.chromosome = hapmap_geno$snp.chromosome,
    snp.position = hapmap_geno$snp.position,
    snp.allele = hapmap_geno$snp.allele,
    snpfirstdim = TRUE)