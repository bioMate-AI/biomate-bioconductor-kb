library(screenCounter)
library(Biostrings)

# Our pool of known variable sequences, one per barcode:
known <- c("AAAAAAAA", "CCCCCCCC", "GGGGGGGG", "TTTTTTTT")

# Mocking up some sequence data, where each read randomly contains
# one of the variable sequences, flanked by constant regions.
set.seed(123)
chosen <- sample(known, 1000, replace=TRUE)
reads <- sprintf("GTAC%sCATG", chosen)
names(reads) <- sprintf("READ_%i", seq_along(reads))

# Writing to the required FASTQ file in the working directory
writeXStringSet(DNAStringSet(reads), file="single.fastq", format="fastq")