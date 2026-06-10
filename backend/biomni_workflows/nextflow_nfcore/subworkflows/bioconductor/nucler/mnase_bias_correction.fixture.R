library(nucleR)
library(GenomicRanges)
library(IRanges)

# Generate synthetic nucleosome map as per vignette
map <- syntheticNucMap(as.ratio=TRUE, wp.num=50, fuz.num=25)

# Calculate coverage for nucleosomal and control reads
exp <- coverage(map$syn.reads)
ctr <- coverage(map$ctr.reads)

# Assign to names that might be expected by the workflow
nucleosomal_coverage <- exp
control_coverage <- ctr

# Save to the required RData files
save(exp, nucleosomal_coverage, file="nucleosomal_coverage.RData")
save(ctr, control_coverage, file="control_coverage.RData")