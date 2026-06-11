library(NoRCE)
library(rtracklayer)
library(GenomicRanges)

# Try to locate the file shipped with the package as mentioned in the vignette
regions_file <- system.file("extdata", "ncRegion.txt", package = "NoRCE")

if (file.exists(regions_file) && regions_file != "") {
    # Copy the existing file to the working directory
    file.copy(regions_file, "ncRegion.txt", overwrite = TRUE)
} else {
    # Construct a small synthetic BED file if it is not shipped
    gr <- GRanges(
        seqnames = c("chr1", "chr2", "chr3"),
        ranges = IRanges(start = c(10000, 20000, 30000), end = c(10500, 20500, 30500)),
        strand = c("+", "-", "*"),
        name = c("ncRNA_1", "ncRNA_2", "ncRNA_3")
    )
    rtracklayer::export(gr, "ncRegion.txt", format = "BED")
}