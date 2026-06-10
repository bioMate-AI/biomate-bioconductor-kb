library(Rbec)

fq_src <- system.file("extdata", "test_raw_merged_reads.fastq.gz", package="Rbec")
if (file.exists(fq_src)) {
    file.copy(fq_src, "test_raw_merged_reads.fastq.gz", overwrite = TRUE)
} else {
    stop("Source file test_raw_merged_reads.fastq.gz not found in Rbec package.")
}

ref_src <- system.file("extdata", "test_ref.fasta", package="Rbec")
if (file.exists(ref_src)) {
    file.copy(ref_src, "test_ref.fasta", overwrite = TRUE)
} else {
    stop("Source file test_ref.fasta not found in Rbec package.")
}