library("GenomicDistributions")
library("rtracklayer")
library("GenomicRanges")

queryFile_pkg <- system.file("extdata", "vistaEnhancers.bed.gz", package="GenomicDistributions")

if (file.exists(queryFile_pkg)) {
    query <- rtracklayer::import(queryFile_pkg)
} else {
    # Fallback synthetic data if the package file is missing
    query <- GRanges(
        seqnames = Rle(c("chr1", "chr2"), c(2, 1)),
        ranges = IRanges(start = c(1000, 3000, 2000), end = c(1500, 3500, 2500)),
        strand = Rle(strand(c("-", "+", "*")))
    )
}

rtracklayer::export(query, "queryFile.bed", format="BED")