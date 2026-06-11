library(BSgenome)
library(Biostrings)

ce2dict0_file <- system.file("extdata", "ce2dict0.fa", package="BSgenome")

if (file.exists(ce2dict0_file)) {
    file.copy(ce2dict0_file, "ce2dict0.fa", overwrite = TRUE)
} else {
    ce2dict0 <- DNAStringSet(c(
        "ACCCAGGGC",
        "AAGCCTAAGCCTAAGCCTAA"
    ))
    names(ce2dict0) <- c("pattern1", "pattern2")
    writeXStringSet(ce2dict0, "ce2dict0.fa", format="fasta")
}