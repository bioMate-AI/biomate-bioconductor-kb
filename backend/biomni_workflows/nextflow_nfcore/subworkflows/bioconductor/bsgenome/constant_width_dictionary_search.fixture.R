library(BSgenome)
library(Biostrings)

ce2dict0_file <- system.file("extdata", "ce2dict0.fa", package="BSgenome")

if (file.exists(ce2dict0_file)) {
    ce2dict0 <- readDNAStringSet(ce2dict0_file, "fasta")
    writeXStringSet(ce2dict0, filepath="ce2dict0.fa", format="fasta")
} else {
    # Fallback synthetic data if the file is not found
    ce2dict0 <- DNAStringSet(c(
        "pattern1" = "ACCCAGGGC",
        "pattern2" = "AAGCCTAAGCCTAAGCCTAA"
    ))
    writeXStringSet(ce2dict0, filepath="ce2dict0.fa", format="fasta")
}