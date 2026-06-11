library("rBLAST")
library("Biostrings")

# 1. Reproduce the vignette's data-preparation code
# Find the example FASTA file shipped with the package
fasta_file <- list.files(system.file(package = "rBLAST"), pattern = "RNA_example.fasta", recursive = TRUE, full.names = TRUE)

if (length(fasta_file) > 0 && file.exists(fasta_file[1])) {
    seq <- readRNAStringSet(fasta_file[1])
} else {
    # Fallback synthetic data if the package example file is not found
    seq <- RNAStringSet(c(
        "AB015560.1" = paste0(rep(c("A", "G", "U", "C"), 60), collapse = ""),
        "D14432.1" = paste0(rep(c("G", "C", "A", "U"), 60), collapse = "")
    ))
}

# 2. Serialize the object to the declared input file: RNA_example.fasta
writeXStringSet(seq, filepath = "RNA_example.fasta")

# Create the fragment as done in the vignette
fragment <- subseq(seq[1], start = 101, end = 200)

# Serialize the fragment to the declared input file: fragment
writeXStringSet(fragment, filepath = "fragment")