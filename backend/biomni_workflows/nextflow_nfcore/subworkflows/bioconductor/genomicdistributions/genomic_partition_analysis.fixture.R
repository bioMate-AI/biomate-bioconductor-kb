library("GenomicDistributions")
library("rtracklayer")
library("GenomicRanges")

queryFile_builtin <- system.file("extdata", "vistaEnhancers.bed.gz", package="GenomicDistributions")

if (file.exists(queryFile_builtin)) {
    query <- rtracklayer::import(queryFile_builtin)
} else {
    # Fallback synthetic data if the package file is missing
    query <- GRanges(
        seqnames = Rle(c("chr1", "chr2"), c(5, 5)),
        ranges = IRanges(start = seq(1000, 10000, by = 1000), width = 500)
    )
}

rtracklayer::export(query, "queryFile.bed", format="BED")