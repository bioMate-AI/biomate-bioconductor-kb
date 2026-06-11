library(Rbwa)

fasta_src <- system.file("fasta", "chr12.fa", package="Rbwa")
fastq_src <- system.file("fastq", "sequences.fastq", package="Rbwa")

if (file.exists(fasta_src)) {
    file.copy(fasta_src, "fasta", overwrite = TRUE)
} else {
    stop("FASTA file not found in Rbwa package")
}

if (file.exists(fastq_src)) {
    file.copy(fastq_src, "fastq", overwrite = TRUE)
} else {
    stop("FASTQ file not found in Rbwa package")
}