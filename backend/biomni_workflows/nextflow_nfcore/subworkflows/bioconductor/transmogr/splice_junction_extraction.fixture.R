library(rtracklayer)
library(GenomicRanges)

# Attempt to locate the exact file shipped with the package as referenced in the vignette
f <- system.file("extdata", "gencode.v44.subset.gtf.gz", package = "transmogR")

if (f != "" && file.exists(f)) {
    file.copy(f, "annotations.gtf.gz", overwrite = TRUE)
} else {
    # Fallback: construct a synthetic GTF matching the vignette's structure
    gr <- GRanges(
        seqnames = "chr1",
        ranges = IRanges(start = c(89295, 120775, 112700), end = c(120932, 120932, 112804)),
        strand = "-",
        source = "rtracklayer",
        type = c("transcript", "exon", "exon"),
        gene_id = "ENSG00000238009.6",
        transcript_id = "ENST00000466430.5",
        exon_number = c(NA, "1", "2")
    )
    export(gr, "annotations.gtf.gz", format = "gtf")
}