library(screenCounter)
library(Biostrings)

set.seed(123)

# Generate random barcodes of length 14 as per the vignette's template structure
# CAGCAGCATGCTGNNNNNNNNNNNNNNCAGCATCGTGC
random_barcodes <- replicate(1000, paste(sample(c("A", "C", "G", "T"), 14, replace = TRUE), collapse = ""))

# Flank with constant regions
reads <- sprintf("CAGCAGCATGCTG%sCAGCATCGTGC", random_barcodes)
names(reads) <- sprintf("READ_%i", seq_along(reads))

# Write to the required FASTQ file
writeXStringSet(DNAStringSet(reads), file="random.fastq", format="fastq")