library(Rfastp)

pe_read1_src <- system.file("extdata", "reads1.fastq.gz", package="Rfastp")
if (file.exists(pe_read1_src)) {
    file.copy(pe_read1_src, "reads1.fastq.gz", overwrite = TRUE)
} else {
    con <- gzfile("reads1.fastq.gz", "w")
    writeLines(c("@read1", "ACGTACGTACGT", "+", "IIIIIIIIIIII"), con)
    close(con)
}

pe_read2_src <- system.file("extdata", "reads2.fastq.gz", package="Rfastp")
if (file.exists(pe_read2_src)) {
    file.copy(pe_read2_src, "reads2.fastq.gz", overwrite = TRUE)
} else {
    con <- gzfile("reads2.fastq.gz", "w")
    writeLines(c("@read1", "TGCATGCATGCA", "+", "IIIIIIIIIIII"), con)
    close(con)
}