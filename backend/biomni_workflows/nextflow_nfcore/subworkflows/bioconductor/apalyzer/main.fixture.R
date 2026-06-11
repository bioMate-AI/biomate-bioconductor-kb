library(APAlyzer)
library(TBX20BamSubset)
library(Rsamtools)

# 1. Generate flsall (named vector of paths to BAM files)
flsall <- getBamFileList()
saveRDS(flsall, "flsall.rds")

# 2. Generate refUTRraw (data frame of 3'UTR PAS genomic information)
# Using coordinates from the vignette's chr19 example
refUTRraw <- data.frame(
  gene_symbol = c("1700020D05Rik", "1810009A15Rik"),
  Chrom = c("chr19", "chr19"),
  Strand = c("-", "+"),
  First = c(5495277, 5500000),
  Last = c(5492231, 5505000),
  cdsend = c(5502867, 5490000),
  stringsAsFactors = FALSE
)
saveRDS(refUTRraw, "refUTRraw.rds")

# 3. Generate dfIPA (data frame of intronic PAS genomic information)
# Using coordinates from the vignette's chr19 example
dfIPA <- data.frame(
  PASid = c("chr19:45894071:-", "chr19:45952090:-"),
  gene_symbol = c("9130011E15Rik", "9130011E15Rik"),
  Chrom = c("chr19", "chr19"),
  Strand = c("-", "-"),
  Pos = c(45894071, 45952090),
  upstreamSS = c(45895000, 45953000),
  downstreamSS = c(45893000, 45951000),
  stringsAsFactors = FALSE
)
saveRDS(dfIPA, "dfIPA.rds")

# 4. Generate dfLE (data frame of 3' least exon genomic information)
# Using coordinates from the vignette's chr19 example
dfLE <- data.frame(
  gene_symbol = c("9130011E15Rik"),
  Chrom = c("chr19"),
  Strand = c("-"),
  LEstart = c(45890000),
  TES = c(45880000),
  stringsAsFactors = FALSE
)
saveRDS(dfLE, "dfLE.rds")