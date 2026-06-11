library(ChIPsim)
library(Biostrings)

set.seed(1)

chrLen <- c(2e5, 1e5)
chromosomes <- sapply(chrLen, function(n) paste(sample(DNA_BASES, n, replace = TRUE), collapse = ""))
names(chromosomes) <- paste("CHR", seq_along(chromosomes), sep="")
genome <- DNAStringSet(chromosomes)

writeXStringSet(genome, filepath = "genome.fasta", format = "fasta")