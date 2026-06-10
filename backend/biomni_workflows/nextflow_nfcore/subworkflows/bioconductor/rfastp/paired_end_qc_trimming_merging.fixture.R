library(Rfastp)

pe_read1 <- system.file("extdata", "reads1.fastq.gz", package="Rfastp")
pe_read2 <- system.file("extdata", "reads2.fastq.gz", package="Rfastp")

if (file.exists(pe_read1) && file.exists(pe_read2)) {
    file.copy(pe_read1, "reads1.fastq.gz", overwrite = TRUE)
    file.copy(pe_read2, "reads2.fastq.gz", overwrite = TRUE)
} else {
    # Fallback to creating minimal valid FASTQ files if not found in extdata
    fq1 <- c("@read1/1", "ACGTACGTACGTACGT", "+", "IIIIIIIIIIIIIIII")
    fq2 <- c("@read1/2", "TGCATGCATGCATGCA", "+", "IIIIIIIIIIIIIIII")
    
    gz1 <- gzfile("reads1.fastq.gz", "w")
    writeLines(fq1, gz1)
    close(gz1)
    
    gz2 <- gzfile("reads2.fastq.gz", "w")
    writeLines(fq2, gz2)
    close(gz2)
}