library(pqsfinder)
library(Biostrings)

seq <- DNAString("TTTTGGGCGGGAGGAGTGGAGTTTTTAACCCCAAAAATTTGGGAGGGTGGGTGGGAGAA")
ss <- DNAStringSet(seq)
names(ss) <- "chr1"

writeXStringSet(ss, filepath = "sequence.fa", format = "fasta")