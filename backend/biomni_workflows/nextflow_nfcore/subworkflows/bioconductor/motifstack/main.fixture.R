library(motifStack)

# Locate the shipped PCM file
pcm_file <- system.file("extdata", "bin_SOLEXA.pcm", package = "motifStack")

# Read the raw PCM file
pcm <- read.table(pcm_file)

# Format the matrix to have rows representing bases and columns representing positions
# (as demonstrated in the vignette and required by the spec)
pcm <- pcm[, 3:ncol(pcm)]
rownames(pcm) <- c("A", "C", "G", "T")

# Write the formatted matrix to the expected input file
# Using col.names = NA ensures that read.table("motif_matrix.txt") will 
# automatically use the first column as row names.
write.table(pcm, file = "motif_matrix.txt", sep = "\t", quote = FALSE, col.names = NA)