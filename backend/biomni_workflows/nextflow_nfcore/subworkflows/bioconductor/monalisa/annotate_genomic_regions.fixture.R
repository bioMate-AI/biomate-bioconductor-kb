library(monaLisa)
library(GenomicRanges)
library(rtracklayer)

# 1. Create promoters.bed
# The vignette uses LMRsESNPmerged.gr.rds as the example genomic regions
lmrfile <- system.file("extdata", "LMRsESNPmerged.gr.rds", package = "monaLisa")

if (file.exists(lmrfile)) {
    lmr <- readRDS(lmrfile)
    # Export a subset to BED format to match the workflow's import("promoters.bed", format = "bed")
    export(lmr[1:500], "promoters.bed", format = "bed")
} else {
    # Fallback if the RDS is not found
    gr <- GRanges(seqnames = "chr1", 
                  ranges = IRanges(start = c(3549153, 3680914, 3913315), 
                                   end = c(3550201, 3682164, 3914523)),
                  strand = "*")
    export(gr, "promoters.bed", format = "bed")
}

# 2. Create motifs.jaspar
# The workflow uses readJASPARMatrix("motifs.jaspar", matrixClass = "PFM")
# We construct a valid JASPAR format file with a couple of example motifs
jaspar_text <- ">MA0004.1\tArnt
A [ 4 19  0  0  0  0 ]
C [16  0 20  0  0  0 ]
G [ 0  1  0 20  0 20 ]
T [ 0  0  0  0 20  0 ]
>MA0006.1\tAhr::Arnt
A [ 3  0  0  0  0  0 ]
C [ 0  0  0 24  0  0 ]
G [ 0 24  0  0  0  0 ]
T [21  0 24  0 24 24 ]"

writeLines(jaspar_text, "motifs.jaspar")