suppressPackageStartupMessages({
    library(APAlyzer)
    library(TBX20BamSubset)
    library(Rsamtools)
})

# 1. Generate and save flsall (List of RNA-seq BAM files)
flsall <- getBamFileList()
saveRDS(flsall, "flsall")

# 2. Generate and save mm9_REF.RData (Pre-built PAS reference data)
# Creating synthetic data frames matching the structure expected by APAlyzer
refUTRraw <- data.frame(
  gene_symbol = c("1700020D05Rik", "1810009A15Rik"),
  Chrom = c("chr19", "chr19"),
  Strand = c("-", "+"),
  First = c(5495277, 6000000),
  Last = c(5492231, 6005000),
  cdsend = c(5502867, 5999000),
  stringsAsFactors = FALSE
)

dfIPA <- data.frame(
  PASid = c("chr19:45894071:-", "chr19:45952090:-"),
  gene_symbol = c("9130011E15Rik", "9130011E15Rik"),
  Chrom = c("chr19", "chr19"),
  Strand = c("-", "-"),
  Pos = c(45894071, 45952090),
  upstreamSS = c(45894000, 45952000),
  downstreamSS = c(45894100, 45952100),
  stringsAsFactors = FALSE
)

dfLE <- data.frame(
  gene_symbol = c("9130011E15Rik", "OtherGene"),
  Chrom = c("chr19", "chr19"),
  Strand = c("-", "+"),
  LEstart = c(45890000, 50000000),
  TES = c(45895000, 50005000),
  stringsAsFactors = FALSE
)

save(refUTRraw, dfIPA, dfLE, file = "mm9_REF.RData")