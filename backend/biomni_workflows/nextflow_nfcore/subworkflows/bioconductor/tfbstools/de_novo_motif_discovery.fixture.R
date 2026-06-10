library(TFBSTools)
library(Biostrings)

# Construct a synthetic FASTA file containing DNA sequences
# as required by the input specification (crp0.s)
dna_seqs <- DNAStringSet(c(
  seq1 = "ACGTCGATCGATCGATCGATCGATCGATCG",
  seq2 = "GCTAGCTAGCTAGCTAGCTAGCTAGCTAGC",
  seq3 = "ATCGATCGATCGATCGATCGATCGATCGAT",
  seq4 = "TTAACCGGTTTTAACCGGTTTTAACCGGTT"
))

writeXStringSet(dna_seqs, filepath = "crp0.s", format = "fasta")