library(QSutils)
library(Biostrings)

toy_fna <- system.file("extdata", "ToyData_10_50_1000.fna", package="QSutils")

if (file.exists(toy_fna)) {
    file.copy(toy_fna, "Unknown-Genotype.fna", overwrite = TRUE)
    file.copy(toy_fna, "GenotypeStandards_A-H.fas", overwrite = TRUE)
} else {
    fna_content <- c(
        ">Hpl_0_0001|464|46.4",
        "CACCCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT",
        ">Hpl_1_0001|62|6.2",
        "CACTCTGTGACCAGTGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT",
        ">Hpl_1_0002|39|3.9",
        "CACCCTGTGACCAGCGTGTGCGAGTTTGGTGCCCCGTTGGCATTGACTAT"
    )
    writeLines(fna_content, "Unknown-Genotype.fna")
    writeLines(fna_content, "GenotypeStandards_A-H.fas")
}