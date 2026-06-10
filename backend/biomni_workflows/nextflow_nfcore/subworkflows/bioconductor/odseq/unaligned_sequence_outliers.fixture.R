library(odseq)
library(Biostrings)

set.seed(93)
data("seqs", package = "odseq")

if (is.character(seqs)) {
    seqs <- AAStringSet(seqs)
} else if (!inherits(seqs, "XStringSet")) {
    seqs <- as(seqs, "AAStringSet")
}

writeXStringSet(seqs, filepath = "seqs.fasta")