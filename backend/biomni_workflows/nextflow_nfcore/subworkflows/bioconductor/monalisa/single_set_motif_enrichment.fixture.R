library(monaLisa)
library(GenomicRanges)
library(rtracklayer)

# 1. Generate foreground_peaks.bed
lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")

if (file.exists(lmrfile)) {
    lmr <- readRDS(lmrfile)
    set.seed(1)
    lmrsel <- lmr[sample(x = length(lmr), size = min(1000, length(lmr)), replace = FALSE)]
    rtracklayer::export(lmrsel, con = "foreground_peaks.bed", format = "bed")
} else {
    # Fallback if the vignette data file is not shipped
    lmrsel <- GRanges(
        seqnames = "chr1", 
        ranges = IRanges(
            start = c(3549153, 3680914, 3913315, 3953500, 4150457), 
            end = c(3550201, 3682164, 3914523, 3954157, 4151567)
        ),
        deltaMeth = c(0.3190299, 0.0657352, 0.4803313, 0.4504727, 0.5014768)
    )
    rtracklayer::export(lmrsel, con = "foreground_peaks.bed", format = "bed")
}

# 2. Generate motifs.jaspar
jaspar_text <- ">MA0001.1 AGL3
A  [ 0  3 79 40 66 48 65 11 65  0 ]
C  [94 75  4  3  1  2  5  2  3  3 ]
G  [ 1  0  3  4  1  0  5  3 28 88 ]
T  [ 2 19 11 50 29 47 22 81  1  6 ]
>MA0002.1 RUNX1
A  [ 10 12  4  1  2  2  0  0  0  8 13 ]
C  [  2  2  7  1  0  8  0  0  1  2  2 ]
G  [  3  1  1  0 23  0 26 26  0  0  4 ]
T  [  8 11 14 24  1 16  0  0 25 16  7 ]"

writeLines(jaspar_text, "motifs.jaspar")