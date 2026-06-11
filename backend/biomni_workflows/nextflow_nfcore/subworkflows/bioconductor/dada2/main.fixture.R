library(dada2)

# Identify forward reads from the package's extdata
fwd_candidates <- c(
    system.file("extdata", "forward_reads.fastq.gz", package="dada2"),
    system.file("extdata", "sam1F.fastq.gz", package="dada2"),
    list.files(system.file("extdata", package="dada2"), pattern="forward.*\\.fastq\\.gz$", full.names=TRUE)[1],
    list.files(system.file("extdata", package="dada2"), pattern="F\\.fastq\\.gz$", full.names=TRUE)[1]
)
fwd_file <- fwd_candidates[!is.na(fwd_candidates) & file.exists(fwd_candidates)][1]

# Identify reverse reads from the package's extdata
rev_candidates <- c(
    system.file("extdata", "reverse_reads.fastq.gz", package="dada2"),
    system.file("extdata", "sam1R.fastq.gz", package="dada2"),
    list.files(system.file("extdata", package="dada2"), pattern="reverse.*\\.fastq\\.gz$", full.names=TRUE)[1],
    list.files(system.file("extdata", package="dada2"), pattern="R\\.fastq\\.gz$", full.names=TRUE)[1]
)
rev_file <- rev_candidates[!is.na(rev_candidates) & file.exists(rev_candidates)][1]

# Copy or generate the forward reads file
if (!is.na(fwd_file)) {
    file.copy(fwd_file, "sample_F.fastq.gz", overwrite = TRUE)
} else {
    gz1 <- gzfile("sample_F.fastq.gz", "w")
    writeLines(c("@SEQ1", "GATTACA", "+", "IIIIIII"), gz1)
    close(gz1)
}

# Copy or generate the reverse reads file
if (!is.na(rev_file)) {
    file.copy(rev_file, "sample_R.fastq.gz", overwrite = TRUE)
} else {
    gz2 <- gzfile("sample_R.fastq.gz", "w")
    writeLines(c("@SEQ1", "TGTAATC", "+", "IIIIIII"), gz2)
    close(gz2)
}