library(QSutils)
library(Biostrings)

filepath <- system.file("extdata", "ToyData_10_50_1000.fna", package="QSutils")

if (file.exists(filepath)) {
    file.copy(filepath, "Unknown-Genotype.fna", overwrite = TRUE)
    file.copy(filepath, "GenotypeStandards_A-H.fas", overwrite = TRUE)
} else {
    seqs <- DNAStringSet(c(
        "CACCCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT",
        "CACTCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT",
        "CACCCTGTGACCAGCGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT",
        "CACCCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAC"
    ))
    names(seqs) <- c(
        "Hpl_0_0001|464|46.4",
        "Hpl_1_0001|62|6.2",
        "Hpl_1_0002|39|3.9",
        "Hpl_1_0003|27|2.7"
    )
    writeXStringSet(seqs, "Unknown-Genotype.fna")
    writeXStringSet(seqs, "GenotypeStandards_A-H.fas")
}