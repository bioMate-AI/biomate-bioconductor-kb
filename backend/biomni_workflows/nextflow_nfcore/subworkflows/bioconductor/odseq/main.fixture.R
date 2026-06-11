library(odseq)
library(Biostrings)

set.seed(93)
data("seqs", package = "odseq")

writeXStringSet(seqs, filepath = "seqs")
writeXStringSet(seqs, filepath = "seqs.fa")