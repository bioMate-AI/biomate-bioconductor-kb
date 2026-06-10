library(branchpointer)

# 1. gencode.v26.annotation.gtf
small_gtf <- system.file("extdata", "gencode.v26.annotation.small.gtf", package = "branchpointer")
if (file.exists(small_gtf)) {
    file.copy(small_gtf, "gencode.v26.annotation.gtf", overwrite = TRUE)
} else {
    # Fallback dummy GTF
    gtf_content <- 'chr17\tHAVANA\texon\t43045000\t43046000\t.\t-\t.\tgene_id "ENSG00000012048.21"; transcript_id "ENST00000357654.8"; exon_number 1; exon_id "ENSE00003512345.1";\n'
    cat(gtf_content, file = "gencode.v26.annotation.gtf")
}

# 2. SNP_example.txt
snp_file <- system.file("extdata", "SNP_example.txt", package = "branchpointer")
if (file.exists(snp_file)) {
    file.copy(snp_file, "SNP_example.txt", overwrite = TRUE)
} else {
    # Fallback synthetic SNP file
    snp_data <- data.frame(
        id = c("rs587776767", "rs786205083"),
        chromosome = c("chr17", "chr13"),
        chrom_start = c(43045820, 32346783),
        strand = c("-", "+"),
        ref_allele = c("A", "C"),
        alt_allele = c("G", "T")
    )
    write.table(snp_data, "SNP_example.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}