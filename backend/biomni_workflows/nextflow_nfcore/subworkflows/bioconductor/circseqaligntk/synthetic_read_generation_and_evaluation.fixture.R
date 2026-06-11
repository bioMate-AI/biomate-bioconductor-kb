library(CircSeqAlignTk)

# Locate the example FASTA file shipped with the package
genome_seq_src <- system.file("extdata", "FR851463.fa", package = "CircSeqAlignTk")

# Copy it to the working directory as expected by the workflow
if (file.exists(genome_seq_src)) {
    file.copy(from = genome_seq_src, to = "genome_seq.fa", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA if the file is missing
    writeLines(
        c(">FR851463", 
          "CGGAACTAAACTCGTGGTTCCTGTGGTTCACACCTGACCTCCTGAGCAGGAAAGAAAAAAGAATTGCGGCTCGGAGGAGCGCTTCAGGGATCCCCGGGGAAACCTGGAGCG"), 
        "genome_seq.fa"
    )
}