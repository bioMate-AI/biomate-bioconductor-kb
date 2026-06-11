library(pqsfinder)
library(Biostrings)

# Reproduce the sequence from the vignette's basic quadruplex detection example
seq_string <- "TTTTGGGCGGGAGGAGTGGAGTTTTTAACCCCAAAAATTTGGGAGGGTGGGTGGGAGAA"

# Convert to a DNAStringSet as expected by the workflow's readDNAStringSet()
seq_set <- DNAStringSet(c("chr1" = seq_string))

# Serialize to the required input file
writeXStringSet(seq_set, filepath = "sequence.fa", format = "fasta")