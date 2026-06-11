library(fCCAC)
library(rtracklayer)
library(GenomicRanges)

# Locate the shipped files in the package's extdata directory
extdata_dir <- system.file("extdata", package="fCCAC")
all_files <- list.files(extdata_dir, full.names=TRUE, recursive=TRUE)

# Helper function to find files matching expected patterns
find_file <- function(patterns) {
    for (p in patterns) {
        res <- all_files[grep(p, all_files, ignore.case=TRUE)]
        if (length(res) > 0) return(res[1])
    }
    return(NA)
}

# Match the ground truth names or the vignette names
peak_src <- find_file(c("peaks\\.bed$", "chr21_merged_ACT_K4\\.bed$", "\\.bed$"))
bw1_src <- find_file(c("sample1\\.bw$", "chr21_H3K4me3_1\\.bw$", "1\\.bw$"))
bw2_src <- find_file(c("sample2\\.bw$", "chr21_H3K4me3_2\\.bw$", "2\\.bw$"))
bw3_src <- find_file(c("sample3\\.bw$", "chr21_H3K4me3_3\\.bw$", "3\\.bw$"))

# 1. peakFile.bed
if (!is.na(peak_src)) {
    file.copy(peak_src, "peakFile.bed", overwrite=TRUE)
} else {
    # Fallback: create a synthetic BED file
    gr <- GRanges("chr21", IRanges(start=c(40000000, 40010000), end=c(40005000, 40015000)))
    export(gr, "peakFile.bed")
}

# 2. bigwig1.bw
if (!is.na(bw1_src)) {
    file.copy(bw1_src, "bigwig1.bw", overwrite=TRUE)
} else {
    # Fallback: create a synthetic BigWig file
    gr1 <- GRanges("chr21", IRanges(start=seq(40000000, 40015000, by=100), width=100), score=runif(151))
    seqlengths(gr1) <- c(chr21=48129895)
    export(gr1, "bigwig1.bw")
}

# 3. bigwig2.bw
if (!is.na(bw2_src)) {
    file.copy(bw2_src, "bigwig2.bw", overwrite=TRUE)
} else {
    # Fallback: create a synthetic BigWig file
    gr2 <- GRanges("chr21", IRanges(start=seq(40000000, 40015000, by=100), width=100), score=runif(151))
    seqlengths(gr2) <- c(chr21=48129895)
    export(gr2, "bigwig2.bw")
}

# 4. bigwig3.bw
if (!is.na(bw3_src)) {
    file.copy(bw3_src, "bigwig3.bw", overwrite=TRUE)
} else {
    # Fallback: create a synthetic BigWig file
    gr3 <- GRanges("chr21", IRanges(start=seq(40000000, 40015000, by=100), width=100), score=runif(151))
    seqlengths(gr3) <- c(chr21=48129895)
    export(gr3, "bigwig3.bw")
}