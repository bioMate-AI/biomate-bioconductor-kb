library(icetea)

extdata_dir <- system.file("extdata", package = "icetea")

# Locate the shipped files
r1_file <- list.files(extdata_dir, pattern = "mapcap_test_R1\\.fastq\\.gz$", recursive = TRUE, full.names = TRUE)[1]
r2_file <- list.files(extdata_dir, pattern = "mapcap_test_R2\\.fastq\\.gz$", recursive = TRUE, full.names = TRUE)[1]
genome_file <- list.files(extdata_dir, pattern = "genome\\.fa$", recursive = TRUE, full.names = TRUE)[1]

# Copy R1 FASTQ
if (!is.na(r1_file) && file.exists(r1_file)) {
    file.copy(r1_file, "mapcap_test_R1.fastq.gz", overwrite = TRUE)
} else {
    # Fallback synthetic FASTQ
    writeLines(c("@SEQ_ID", "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT", "+", "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"), "mapcap_test_R1.fastq")
    system("gzip -f mapcap_test_R1.fastq")
}

# Copy R2 FASTQ
if (!is.na(r2_file) && file.exists(r2_file)) {
    file.copy(r2_file, "mapcap_test_R2.fastq.gz", overwrite = TRUE)
} else {
    # Fallback synthetic FASTQ
    writeLines(c("@SEQ_ID", "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT", "+", "!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65"), "mapcap_test_R2.fastq")
    system("gzip -f mapcap_test_R2.fastq")
}

# Copy Reference Genome
if (!is.na(genome_file) && file.exists(genome_file)) {
    file.copy(genome_file, "reference_genome.fa", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA
    writeLines(c(">chr1", "GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT"), "reference_genome.fa")
}