# Real user-style input: a 9-column BED file describing a karyotype.
# chromDraw requires the first nine BED fields (chrom, start, end, name, score,
# strand, thickStart, thickEnd, itemRgb). This is a genuine multi-chromosome
# karyotype the user would supply, not a packaged demo dataset.

bed_data <- data.frame(
    chrom      = c("chr1", "chr1", "chr1", "chr2", "chr2", "chr2", "chr3", "chr3"),
    chromStart = c(0,        50000000, 60000000, 0,        40000000, 50000000, 0,        30000000),
    chromEnd   = c(50000000, 60000000, 90000000, 40000000, 50000000, 80000000, 30000000, 65000000),
    name       = c("1p", "CEN1", "1q", "2p", "CEN2", "2q", "3p", "3q"),
    score      = c(0, 0, 0, 0, 0, 0, 0, 0),
    strand     = c("+", "+", "+", "+", "+", "+", "+", "+"),
    thickStart = c(0,        50000000, 60000000, 0,        40000000, 50000000, 0,        30000000),
    thickEnd   = c(50000000, 60000000, 90000000, 40000000, 50000000, 80000000, 30000000, 65000000),
    itemRgb    = c("255,255,0", "255,0,0", "0,255,255", "255,255,0", "255,0,0",
                   "0,255,255", "255,255,0", "0,255,255")
)
write.table(bed_data, "bed_file.bed", sep = "\t", quote = FALSE,
            row.names = FALSE, col.names = FALSE)
