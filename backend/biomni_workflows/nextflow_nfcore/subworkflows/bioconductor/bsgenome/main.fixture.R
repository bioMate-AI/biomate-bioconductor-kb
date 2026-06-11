library(BSgenome)
library(Biostrings)

ce2dict0_file <- system.file("extdata", "ce2dict0.fa", package="BSgenome")

if (file.exists(ce2dict0_file)) {
    file.copy(ce2dict0_file, "ce2dict0.fa", overwrite = TRUE)
} else {
    # Fallback in case the file is missing from the installation
    ce2dict0 <- DNAStringSet(c(
        "pattern1" = "ACCCAGGGC",
        "pattern2" = "AAGCCTAAGCCTAAGCCTAA"
    ))
    writeXStringSet(ce2dict0, "ce2dict0.fa", format="fasta")
}