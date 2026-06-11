library(screenCounter)
library(Biostrings)

# Creating an example dual barcode sequencing experiment.
known.pool1 <- c("AGAGAGAGA", "CTCTCTCTC", "GTGTGTGTG", "CACACACAC")
known.pool2 <- c("ATATATATA", "CGCGCGCGC", "GAGAGAGAG", "CTCTCTCTC")

# Mocking up the barcode sequences.
set.seed(123)
N <- 1000
read <- sprintf("CAGCTACGTACG%sCCAGCTCGATCG%sACACGAGGGTAT", 
    sample(known.pool1, N, replace=TRUE), 
    sample(known.pool2, N, replace=TRUE))
names(read) <- seq_len(N)

# Writing them to the required FASTQ file
writeXStringSet(DNAStringSet(read), filepath="dual_single.fastq", format="fastq")