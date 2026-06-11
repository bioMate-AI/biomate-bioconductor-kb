library(QSutils)
library(Biostrings)

filepath <- system.file("extdata", "Toy.GapsAndNs.fna", package="QSutils")

if (filepath != "" && file.exists(filepath)) {
    file.copy(filepath, "Toy.GapsAndNs.fna", overwrite = TRUE)
} else {
    # Fallback synthetic data if the file is not found
    seqs <- DNAStringSet(c(
        "TGACGCGCACAGAGTGCTGCTAAATGACTGGGTTACCCCGTCGTGGTCGC",
        "TGACGCGCACAGAGTGCTGCTAAATGACTGGGTTACCCCGTCGTGGNCGC",
        "TGACGCGCACAGAGTGCTGCTAAATGACTGGGNTACCCCGTCGTGGTCGC",
        "TGACGCGCACAGAGTGCTGCT-AATGACTGGGTTACCCCGTCGTGGTCGC"
    ))
    names(seqs) <- as.character(1:4)
    writeXStringSet(seqs, "Toy.GapsAndNs.fna")
}