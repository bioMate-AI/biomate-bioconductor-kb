library(katdetectr)

# Generate data that contains non-standard sequences as shown in the vignette
syndata1 <- generateSyntheticData(seqnames = c("chr1_gl000191_random", "chr4_ctg9_hap1"))
syndata2 <- generateSyntheticData(seqnames = "chr1")
syndata <- suppressWarnings(c(syndata1, syndata2))

# Save the VRanges object
saveRDS(syndata, "syndata.rds")

# Construct a dataframe that contains the length of the sequences
# Each column name is the name of the sequence
sequenceLength <- data.frame(
  "chr1_gl000191_random" = 300000000,
  "chr4_ctg9_hap1" = 300000000,
  "chr1" = 300000000,
  check.names = FALSE
)

# Save the sequence lengths data frame
write.csv(sequenceLength, "sequenceLength.csv", row.names = FALSE)