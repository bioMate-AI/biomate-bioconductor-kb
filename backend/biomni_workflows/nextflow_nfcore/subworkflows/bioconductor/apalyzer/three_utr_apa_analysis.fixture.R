library(APAlyzer)
library(TBX20BamSubset)
library(Rsamtools)

# 1. Create flsall (List of RNA-seq BAM files)
# The vignette uses getBamFileList() from TBX20BamSubset
flsall <- getBamFileList()
# Save as an RData file so it can be loaded directly into the environment
save(flsall, file = "flsall")
# Also save as RDS in case the workflow uses readRDS
saveRDS(flsall, "flsall.rds")

# 2. Create mm9_REF.RData (Pre-built PAS reference data)
# We include chr19 data as the vignette subsets to chr19 for the example
refUTRraw <- data.frame(
  gene_symbol = c("Xkr4", "Lypla1", "1700020D05Rik", "1810009A15Rik"),
  Chrom = c("chr1", "chr1", "chr19", "chr19"),
  Strand = c("-", "+", "-", "+"),
  First = c(3204561, 4835237, 5492231, 5500000),
  Last = c(3189814, 4836816, 5495277, 5505000),
  cdsend = c(3206103, 4835097, 5502867, 5490000),
  stringsAsFactors = FALSE
)

dfIPA <- data.frame(
  PASid = c("chr4:32818455:+", "chr4:32837613:+", "chr19:45894071:-", "chr19:45952090:-"),
  gene_symbol = c("Mdn1", "Mdn1", "9130011E15Rik", "9130011E15Rik"),
  Chrom = c("chr4", "chr4", "chr19", "chr19"),
  Strand = c("+", "+", "-", "-"),
  Pos = c(32818455, 32837613, 45894071, 45952090),
  upstreamSS = c(32818305, 32837452, 45895000, 45953000),
  downstreamSS = c(32818889, 32837887, 45893000, 45951000),
  stringsAsFactors = FALSE
)

dfLE <- data.frame(
  gene_symbol = c("0610009O20Rik", "0610010F05Rik", "9130011E15Rik"),
  Chrom = c("chr18", "chr11", "chr19"),
  Strand = c("+", "-", "-"),
  LEstart = c(38421534, 23465136, 45890000),
  TES = c(38425118, 23462079, 45880000),
  stringsAsFactors = FALSE
)

save(refUTRraw, dfIPA, dfLE, file = "mm9_REF.RData")