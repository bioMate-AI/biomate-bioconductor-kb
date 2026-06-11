library(tidyCoverage)
library(rtracklayer)
library(GenomicRanges)

# Locate the example files shipped with the package
bw_file <- system.file("extdata", "MNase.bw", package = "tidyCoverage")
bed_file <- system.file("extdata", "TSSs.bed", package = "tidyCoverage")

# Write the tracks input file
if (file.exists(bw_file)) {
    file.copy(bw_file, "tracks", overwrite = TRUE)
} else {
    # Fallback: create a synthetic BigWig file if the package data is missing
    gr_bw <- GRanges("chr1", IRanges(start = seq(1, 100, by = 10), width = 10), score = runif(10))
    seqlengths(gr_bw) <- c(chr1 = 1000)
    export.bw(gr_bw, "tracks")
}

# Write the features input file
if (file.exists(bed_file)) {
    file.copy(bed_file, "features", overwrite = TRUE)
} else {
    # Fallback: create a synthetic BED file if the package data is missing
    gr_bed <- GRanges("chr1", IRanges(start = seq(1, 100, by = 10), width = 10))
    export.bed(gr_bed, "features")
}