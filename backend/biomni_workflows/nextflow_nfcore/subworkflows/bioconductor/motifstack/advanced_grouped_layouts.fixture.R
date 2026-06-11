library(motifStack)

# Locate the example PCM files shipped with the motifStack package
pcm_files <- dir(file.path(find.package("motifStack"), "extdata"), pattern = "pcm$", full.names = TRUE)

# Import the matrices as a list of pcm objects
pcms <- importMatrix(pcm_files)

# Convert the pcm objects to a list of pfm objects
pfms <- lapply(pcms, function(x) {
  mat <- pcm2pfm(x@mat)
  new("pfm", mat = mat, name = x@name)
})

# Save the list of PFM objects to the declared input file
saveRDS(pfms, "pfms")

# Create a data frame containing numeric annotation values for the motifs
df <- data.frame(
  score = runif(length(pfms)),
  pvalue = runif(length(pfms))
)
rownames(df) <- sapply(pfms, function(x) x@name)

# Save the data frame to the declared input file
saveRDS(df, "df")