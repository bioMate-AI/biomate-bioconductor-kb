library(Rfastp)

# Find and copy the forward paired-end FASTQ file
pe_read1_candidates <- c(
    system.file("extdata", "reads1.fastq.gz", package="Rfastp"),
    list.files(system.file("extdata", package="Rfastp"), pattern="reads1.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE),
    list.files(system.file("extdata", package="Rfastp"), pattern=".*R1.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE)
)
pe_read1_src <- pe_read1_candidates[file.exists(pe_read1_candidates)][1]

if (!is.na(pe_read1_src)) {
    file.copy(pe_read1_src, "pe_read1", overwrite = TRUE)
} else {
    stop("Could not find a suitable forward paired-end FASTQ file in Rfastp extdata.")
}

# Find and copy the reverse paired-end FASTQ file
pe_read2_candidates <- c(
    system.file("extdata", "reads2.fastq.gz", package="Rfastp"),
    list.files(system.file("extdata", package="Rfastp"), pattern="reads2.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE),
    list.files(system.file("extdata", package="Rfastp"), pattern=".*R2.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE)
)
pe_read2_src <- pe_read2_candidates[file.exists(pe_read2_candidates)][1]

if (!is.na(pe_read2_src)) {
    file.copy(pe_read2_src, "pe_read2", overwrite = TRUE)
} else {
    stop("Could not find a suitable reverse paired-end FASTQ file in Rfastp extdata.")
}