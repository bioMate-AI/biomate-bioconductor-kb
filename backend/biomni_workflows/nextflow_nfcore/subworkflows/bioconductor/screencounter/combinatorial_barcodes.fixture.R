library(Biostrings)
library(screenCounter)

# Our pool of known variable sequences:
known1 <- c("AAAA", "CCCC", "GGGG", "TTTT")
known2 <- c("ATTA", "CGGC", "GCCG", "TAAT")

# Mocking up some sequence data, where each read randomly contains
# two of the variable sequences within a template structure.
set.seed(123)
chosen1 <- sample(known1, 1000, replace=TRUE)
chosen2 <- sample(known2, 1000, replace=TRUE)
reads <- sprintf("GTAC%sCATG%sGTAC", chosen1, chosen2)
names(reads) <- sprintf("READ_%i", seq_along(reads))

# Writing to the required FASTQ file.
writeXStringSet(DNAStringSet(reads), file="combo.fastq", format="fastq")