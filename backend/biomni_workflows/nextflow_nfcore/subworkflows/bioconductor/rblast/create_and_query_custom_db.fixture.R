library("rBLAST")
library("Biostrings")

# Copy the example FASTA file to the working directory
fasta_path <- system.file("examples/RNA_example.fasta", package = "rBLAST")
file.copy(fasta_path, "RNA_example.fasta")

# Create the fragment object as shown in the vignette
seq <- readRNAStringSet(fasta_path)
fragment <- subseq(seq[1], start = 101, end = 200)

# Serialize the S4 object to the declared input file
saveRDS(fragment, "fragment")