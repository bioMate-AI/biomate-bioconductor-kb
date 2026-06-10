library(motifStack)

# Locate the example PCM file shipped with the package
pcm_path <- file.path(find.package("motifStack"), "extdata", "bin_SOLEXA.pcm")

# Read and format the PCM data as demonstrated in the vignette
pcm <- read.table(pcm_path)
pcm <- pcm[, 3:ncol(pcm)]
rownames(pcm) <- c("A", "C", "G", "T")

# Convert to a Position Frequency Matrix (PFM) object
motif1 <- new("pfm", mat=pcm2pfm(pcm), name="bin_SOLEXA")

# Create a second PFM object to form a list of motifs
motif2 <- new("pfm", mat=pcm2pfm(pcm), name="bin_SOLEXA_modified")
motif2@mat[, 1] <- c(0.25, 0.25, 0.25, 0.25) # Ensure column sums to 1

# Create the list of PFM objects
pfms <- list(motif1, motif2)

# Serialize to the expected input file
saveRDS(pfms, "pfms")