library(katdetectr)

# Generate synthetic data that contains non-standard sequences as shown in the vignette
syndata1 <- generateSyntheticData(seqnames = c("chr1_gl000191_random", "chr4_ctg9_hap1"))
syndata2 <- generateSyntheticData(seqnames = "chr1")
syndata <- suppressWarnings(c(syndata1, syndata2))

# Save the VRanges object to the expected input file
saveRDS(syndata, "genomic_variants.rds")