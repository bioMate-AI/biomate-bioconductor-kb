library(monaLisa)
library(GenomicRanges)
library(rtracklayer)

# 1. Reproduce the vignette's data preparation
lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")
lmr <- readRDS(lmrfile)

set.seed(1)
lmrsel <- lmr[sample(x = length(lmr), size = 10000, replace = FALSE)]

# 2. Serialize to peaks.bed
# The vignette notes that scores in the 5th column are imported as the "score" metadata column
lmrsel$score <- lmrsel$deltaMeth
rtracklayer::export(lmrsel, "peaks.bed", format = "bed")

# 3. Serialize to methylation_changes.tsv
meth_data <- data.frame(
    chr = as.character(seqnames(lmrsel)),
    start = start(lmrsel),
    end = end(lmrsel),
    deltaMeth = lmrsel$deltaMeth
)
write.table(meth_data, "methylation_changes.tsv", sep = "\t", quote = FALSE, row.names = FALSE)

# 4. Serialize to motifs.jaspar
# Construct a small synthetic JASPAR file that matches the exact format expected by TFBSTools
jaspar_text <- ">MA0001.1 AGL3
A  [ 0  3 79 40 66 48 65 11 65  0 ]
C  [94 75  4  3  1  2  5  2  3  3 ]
G  [ 1  0  3  4  1  0  5  3 28 88 ]
T  [ 2 19 11 50 29 47 22 81  1  6 ]
>MA0002.1 RUNX1
A  [ 10 12  4  1  2  2  0  0  0  8 ]
C  [  2  2  7  1  0  8  0  0  1  2 ]
G  [  3  1  1  0 23  0 26 26  0  0 ]
T  [ 11 11 14 24  1 16  0  0 25 16 ]"
writeLines(jaspar_text, "motifs.jaspar")