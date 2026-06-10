library(monaLisa)
library(GenomicRanges)
library(rtracklayer)

# 1. Load LMRs (Low Methylated Regions) from monaLisa package as shown in the vignette
lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")
lmr <- readRDS(lmrfile)

# 2. Create unchanged and upregulated peaks based on deltaMeth
# We subset the regions to create our two sets of peaks
unchanged_gr <- head(lmr[abs(lmr$deltaMeth) < 0.05], 200)
upregulated_gr <- head(lmr[lmr$deltaMeth > 0.3], 200)

# Clear metadata to ensure clean BED export (only coordinates are needed)
mcols(unchanged_gr) <- NULL
mcols(upregulated_gr) <- NULL

# 3. Export to BED format
rtracklayer::export(unchanged_gr, "unchanged_peaks.bed", format = "bed")
rtracklayer::export(upregulated_gr, "upregulated_peaks.bed", format = "bed")

# 4. Create a synthetic JASPAR motifs file
# TFBSTools::readJASPARMatrix expects standard JASPAR format
jaspar_text <- ">MA0004.1 Arnt
A  [  4  19   0   0   0   0 ]
C  [ 16   0  20   0   0   0 ]
G  [  0   1   0  20   0  20 ]
T  [  0   0   0   0  20   0 ]
>MA0006.1 Ahr::Arnt
A  [  3   0   0   0   0   0 ]
C  [  0  23   0   0   0   0 ]
G  [  0   0  23   0   0  23 ]
T  [ 20   0   0  23  23   0 ]"

writeLines(jaspar_text, "motifs.jaspar")

# Verify files exist
stopifnot(
    file.exists("unchanged_peaks.bed"),
    file.exists("upregulated_peaks.bed"),
    file.exists("motifs.jaspar")
)