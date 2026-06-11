library(monaLisa)
library(GenomicRanges)
library(rtracklayer)

# Load the example dataset provided by the monaLisa package
lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")
lmr <- readRDS(lmrfile)

# Subset to keep the computation time reasonable and file sizes small
set.seed(1)
lmrsel <- lmr[sample(x = length(lmr), size = 1000, replace = FALSE)]

# Write the genomic coordinates to peaks.bed
rtracklayer::export(lmrsel, "peaks.bed", format = "bed")

# Write the associated numerical values (methylation changes) to methylation_changes.tsv
meth_df <- data.frame(deltaMeth = lmrsel$deltaMeth)
write.table(meth_df, "methylation_changes.tsv", sep = "\t", quote = FALSE, row.names = FALSE)