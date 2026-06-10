library(ramwas)

# Create the artificial data which includes the 'bams/' directory
# and other necessary files (bam_list.txt, covariates.txt, Simulated_chromosome.rds)
ramwas0createArtificialData(
    dir = getwd(),
    nsamples = 2,
    nreads = 1000,
    ncpgs = 1000,
    threads = 1
)

# Create the dummy vcftools --counts output file 'count_ALL_chr22.txt'
count_text <- "CHROM\tPOS\tN_ALLELES\tN_CHR\t{ALLELE:COUNT}
22\t16050075\t2\t5008\tA:5008\tG:0
22\t16050115\t2\t5008\tC:5000\tT:8"
writeLines(count_text, "count_ALL_chr22.txt")