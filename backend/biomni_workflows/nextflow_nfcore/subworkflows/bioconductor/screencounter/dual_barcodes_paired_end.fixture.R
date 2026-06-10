library(screenCounter)
library(Biostrings)

# Creating an example dual barcode sequencing experiment.
known.pool1 <- c("AGAGAGAGA", "CTCTCTCTC", "GTGTGTGTG", "CACACACAC")
known.pool2 <- c("ATATATATA", "CGCGCGCGC", "GAGAGAGAG", "CTCTCTCTC")

# Mocking up the barcode sequences.
N <- 1000
set.seed(123)
read1 <- sprintf("CAGCTACGTACG%sCCAGCTCGATCG", sample(known.pool1, N, replace=TRUE))
names(read1) <- seq_len(N)
read2 <- sprintf("TGGGCAGCGACA%sACACGAGGGTAT", sample(known.pool2, N, replace=TRUE))
names(read2) <- seq_len(N)

# Writing them to FASTQ files.
writeXStringSet(DNAStringSet(read1), filepath="read1.fastq", format="fastq")
writeXStringSet(DNAStringSet(read2), filepath="read2.fastq", format="fastq")