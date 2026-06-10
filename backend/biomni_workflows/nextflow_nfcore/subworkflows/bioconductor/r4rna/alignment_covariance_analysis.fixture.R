library(R4RNA)
library(Biostrings)

# Find and copy fasta.txt
fasta_files <- list.files(system.file("extdata", package = "R4RNA"), pattern = "fasta\\.txt$", recursive = TRUE, full.names = TRUE)
if (length(fasta_files) > 0) {
    file.copy(fasta_files[1], "fasta.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data
    fasta <- BStringSet(c(seq1="ACGUACGU", seq2="ACGUACGU"))
    writeXStringSet(fasta, "fasta.txt")
}

# Find and copy vienna.txt
vienna_files <- list.files(system.file("extdata", package = "R4RNA"), pattern = "vienna\\.txt$", recursive = TRUE, full.names = TRUE)
if (length(vienna_files) > 0) {
    file.copy(vienna_files[1], "vienna.txt", overwrite = TRUE)
} else {
    # Fallback synthetic data
    writeLines(c(">seq1", "ACGUACGU", "(((..)))"), "vienna.txt")
}