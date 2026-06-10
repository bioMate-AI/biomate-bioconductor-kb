library(GenomicRanges)
library(chromDraw)

# Reproduce the vignette's example objects
exampleData <- GRanges(seqnames = Rle(c("ACK1"), c(4)), ranges = 
    IRanges(start = c(0, 6700000, 0, 12400000), 
            end = c(6700000, 12400000, 0, 17000000), 
            names = c("A", "B", "CENTROMERE", "C")),  
    color = c("yellow", "yellow", "", "yellow")
)

name <- c("yellow", "red")
r <- c(255, 255)
g <- c(255, 0)
b <- c(0, 0)
exampleColor <- data.frame(name, r, g, b)

# Prepare the required input file: bed_file.bed
# Try to use the package's shipped BED file if available
bed_source <- system.file('extdata', 'bed.bed', package = 'chromDraw')

if (file.exists(bed_source)) {
    file.copy(bed_source, "bed_file.bed", overwrite = TRUE)
} else {
    # Construct a synthetic BED file with the required 9 columns based on the vignette's exampleData
    bed_data <- data.frame(
        chrom = c("ACK1", "ACK1", "ACK1"),
        chromStart = c(0, 6700000, 12400000),
        chromEnd = c(6700000, 12400000, 17000000),
        name = c("A", "B", "C"),
        score = c(0, 0, 0),
        strand = c("+", "+", "+"),
        thickStart = c(0, 6700000, 12400000),
        thickEnd = c(6700000, 12400000, 17000000),
        itemRgb = c("255,255,0", "255,255,0", "255,255,0")
    )
    write.table(bed_data, "bed_file.bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
}