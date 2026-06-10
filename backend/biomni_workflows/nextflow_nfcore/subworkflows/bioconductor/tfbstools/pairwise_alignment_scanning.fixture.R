library(TFBSTools)
library(Biostrings)

# Generate synthetic DNA sequences for the alignment
seq1 <- DNAStringSet(c(seq1 = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"))
seq2 <- DNAStringSet(c(seq2 = "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT"))

# Write the sequences to FASTA files as expected by the workflow
writeXStringSet(seq1, filepath = "alignment_seq1.fasta")
writeXStringSet(seq2, filepath = "alignment_seq2.fasta")