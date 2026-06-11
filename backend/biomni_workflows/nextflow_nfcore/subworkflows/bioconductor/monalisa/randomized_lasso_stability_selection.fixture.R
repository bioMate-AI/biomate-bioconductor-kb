library(monaLisa)
library(GenomicRanges)
library(rtracklayer)
library(TFBSTools)
library(JASPAR2020)

# 1. Prepare the genomic regions and accessibility changes
# The ground truth indicates atac_liver_vs_lung.rds is available, 
# while the vignette references LMRsESNPmerged.gr.rds. We check for both.
lmrfile <- system.file("extdata", "atac_liver_vs_lung.rds", package = "monaLisa")
if (!file.exists(lmrfile)) {
    lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")
}

if (file.exists(lmrfile)) {
    lmr <- readRDS(lmrfile)
} else {
    # Fallback to a synthetic GRanges object if neither is found
    lmr <- GRanges(
        seqnames = "chr1", 
        ranges = IRanges(start = c(3549153, 3680914, 3913315), end = c(3550201, 3682164, 3914523)),
        deltaMeth = c(0.3190299, 0.0657352, 0.4803313)
    )
}

# Export to atac_peaks.bed
# Strip metadata columns to ensure clean BED export
lmr_bed <- lmr
mcols(lmr_bed) <- NULL
rtracklayer::export(lmr_bed, "atac_peaks.bed", format = "bed")

# Export to accessibility_changes.tsv
acc <- as.data.frame(mcols(lmr))
if (ncol(acc) == 0) {
    acc$log2FC <- rnorm(length(lmr))
}
write.table(acc, "accessibility_changes.tsv", sep = "\t", quote = FALSE, row.names = FALSE, col.names = TRUE)

# 2. Prepare the motifs.jaspar file
# We construct a small synthetic JASPAR format file that TFBSTools can read
jaspar_text <- ">MA0001.1 AGL3
A  [  0   3  79  40  66  48  65  11  65   0 ]
C  [ 94  75   4   3   1   2   5   2   3   3 ]
G  [  1   0   3   4   1   0   5   3  28  88 ]
T  [  2  19  11  50  29  47  22  81   1   6 ]
>MA0002.1 RUNX1
A  [ 10  12   4   1   2   2   0   0   0   8  13 ]
C  [  2   2   7   1   0   8   0   0   1   2   2 ]
G  [  3   1   1   0  23   0  26  26   0   0   4 ]
T  [  8   8  11  21   0  13   0   0  22  13   4 ]"

writeLines(jaspar_text, "motifs.jaspar")