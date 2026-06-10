library(odseq)
library(Biostrings)

# Load the example dataset from the odseq package
data("seqs", package = "odseq")

# Ensure the object is an XStringSet for writing
if (!inherits(seqs, "XStringSet")) {
    seqs <- AAStringSet(seqs)
}

# Write the sequences to the expected input file "seqs" in FASTA format
writeXStringSet(seqs, filepath = "seqs", format = "fasta")