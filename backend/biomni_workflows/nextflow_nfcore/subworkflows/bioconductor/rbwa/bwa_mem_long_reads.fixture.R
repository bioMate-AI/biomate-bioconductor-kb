library(Rbwa)

fasta_src <- system.file("fasta", "chr12.fa", package="Rbwa")
fastq_src <- system.file("fastq", "sequences.fastq", package="Rbwa")

if (file.exists(fasta_src)) {
    file.copy(fasta_src, "reference.fa", overwrite = TRUE)
} else {
    writeLines(c(">chr12", 
                 "ACATCAGAAAGAGCGGCAGCAACCCAGCCCCCCTCCAACCTGTGATCCACGGAGGCTGCACTGCGGTGAGTGCTGTGCCTTTTACAGTTCGTACTGTCATGCCCCCTCAGCCAGTCGGCTCTCACCGTGTCCG"), 
               "reference.fa")
}

if (file.exists(fastq_src)) {
    file.copy(fastq_src, "reads.fastq", overwrite = TRUE)
} else {
    writeLines(c("@read1", 
                 "ACATCAGAAAGAGCGGCAG", 
                 "+", 
                 "IIIIIIIIIIIIIIIIIII"), 
               "reads.fastq")
}