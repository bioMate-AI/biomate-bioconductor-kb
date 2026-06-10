library(Rbwa)

# Locate the example files shipped with the Rbwa package as shown in the vignette
fasta_src <- system.file("fasta", "chr12.fa", package="Rbwa")
fastq_src <- system.file("fastq", "sequences.fastq", package="Rbwa")

# Copy the FASTA file to the working directory
if (file.exists(fasta_src)) {
    file.copy(fasta_src, "reference.fa", overwrite = TRUE)
} else {
    # Fallback synthetic FASTA if the package file is missing
    writeLines(c(">chr12", "ACATCAGAAAGAGCGGCAGCAACCCAGCCCCCCTCCAACCTGTGATCCACGGAGGCTGCACTGCGGTGAGTGCTGT"), "reference.fa")
}

# Copy the FASTQ file to the working directory
if (file.exists(fastq_src)) {
    file.copy(fastq_src, "reads.fastq", overwrite = TRUE)
} else {
    # Fallback synthetic FASTQ if the package file is missing
    writeLines(c(
        "@read1",
        "ACATCAGAAAGAGCGGCAG",
        "+",
        "IIIIIIIIIIIIIIIIIII",
        "@read2",
        "CAACCCAGCCCCCCTCCAA",
        "+",
        "IIIIIIIIIIIIIIIIIII"
    ), "reads.fastq")
}