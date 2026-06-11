library(DECIPHER)

example_fas <- system.file("extdata", "Bacteria_175seqs.fas", package="DECIPHER")

if (example_fas != "" && file.exists(example_fas)) {
    file.copy(example_fas, "fas", overwrite = TRUE)
} else {
    # Fallback if the specific file is not found
    dna <- DNAStringSet(c("ATGCGTAC", "CGTACGAT"))
    names(dna) <- c("seq1", "seq2")
    writeXStringSet(dna, "fas")
}