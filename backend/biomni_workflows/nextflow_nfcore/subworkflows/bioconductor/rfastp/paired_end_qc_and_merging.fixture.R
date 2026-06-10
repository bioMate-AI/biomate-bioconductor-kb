library(Rfastp)

# Find candidate files for pe_read1
pe_read1_candidates <- c(
    system.file("extdata", "reads1.fastq.gz", package="Rfastp"),
    list.files(system.file("extdata", package="Rfastp"), pattern="reads1.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE),
    list.files(system.file("extdata", package="Rfastp"), pattern=".*_R1.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE)
)
pe_read1_src <- Filter(file.exists, pe_read1_candidates)[1]

# Find candidate files for pe_read2
pe_read2_candidates <- c(
    system.file("extdata", "reads2.fastq.gz", package="Rfastp"),
    list.files(system.file("extdata", package="Rfastp"), pattern="reads2.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE),
    list.files(system.file("extdata", package="Rfastp"), pattern=".*_R2.*\\.fastq\\.gz$", recursive=TRUE, full.names=TRUE)
)
pe_read2_src <- Filter(file.exists, pe_read2_candidates)[1]

# Copy or create pe_read1
if (!is.na(pe_read1_src)) {
    file.copy(pe_read1_src, "pe_read1", overwrite = TRUE)
} else {
    # Fallback: create a minimal synthetic FASTQ file
    writeLines(c(
        "@SEQ_ID_1/1",
        "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT",
        "+",
        "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"
    ), "pe_read1")
}

# Copy or create pe_read2
if (!is.na(pe_read2_src)) {
    file.copy(pe_read2_src, "pe_read2", overwrite = TRUE)
} else {
    # Fallback: create a minimal synthetic FASTQ file
    writeLines(c(
        "@SEQ_ID_1/2",
        "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT",
        "+",
        "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"
    ), "pe_read2")
}