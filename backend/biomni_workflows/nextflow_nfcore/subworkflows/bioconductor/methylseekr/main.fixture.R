library(MethylSeekR)

# Locate and copy the methylation data file
meth_file <- list.files(system.file("extdata", package="MethylSeekR"), 
                        pattern="Lister2009_imr90_hg38_chr22.tab", 
                        full.names=TRUE)

if (length(meth_file) > 0 && file.exists(meth_file[1])) {
    file.copy(meth_file[1], "Lister2009_imr90_hg38_chr22.tab", overwrite = TRUE)
} else {
    # Fallback: create a synthetic file matching the expected format
    meth_data <- data.frame(
        chr = c("chr22", "chr22", "chr22", "chr22", "chr22", "chr22"),
        pos = c(23299035, 23299065, 23299082, 23299121, 23299129, 23299141),
        T = c(20, 8, 3, 1, 3, 4),
        M = c(19, 8, 3, 1, 3, 4)
    )
    write.table(meth_data, "Lister2009_imr90_hg38_chr22.tab", 
                sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# Locate and copy the SNP data file
snp_file <- list.files(system.file("extdata", package="MethylSeekR"), 
                       pattern="SNVs_hg38_chr22.tab", 
                       full.names=TRUE)

if (length(snp_file) > 0 && file.exists(snp_file[1])) {
    file.copy(snp_file[1], "SNVs_hg38_chr22.tab", overwrite = TRUE)
} else {
    # Fallback: create a synthetic file matching the expected format
    snp_data <- data.frame(
        chr = c("chr22", "chr22", "chr22", "chr22", "chr22", "chr22"),
        pos = c(23299145, 23299263, 23302084, 23302444, 23302607, 23303306)
    )
    write.table(snp_data, "SNVs_hg38_chr22.tab", 
                sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}