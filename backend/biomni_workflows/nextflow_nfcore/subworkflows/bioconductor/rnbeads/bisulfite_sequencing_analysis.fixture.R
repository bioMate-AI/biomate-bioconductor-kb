suppressPackageStartupMessages(library(RnBeads))

# Create a directory for BED files
dir.create("bed", showWarnings = FALSE)

# Create dummy BED files in BisSNP format (default for RnBeads bs.bed.dir import)
# Columns: chrom, start, end, meth_percent, coverage, strand
bed1 <- data.frame(
    chrom = c("chr1", "chr1", "chr2"),
    start = c(10000, 20000, 30000),
    end = c(10001, 20001, 30001),
    meth = c(50, 100, 0),
    cov = c(10, 20, 15),
    strand = c("+", "-", "+")
)

bed2 <- data.frame(
    chrom = c("chr1", "chr1", "chr2"),
    start = c(10000, 20000, 30000),
    end = c(10001, 20001, 30001),
    meth = c(60, 90, 10),
    cov = c(12, 18, 20),
    strand = c("+", "-", "+")
)

write.table(bed1, file = file.path("bed", "sample1.bed"), sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
write.table(bed2, file = file.path("bed", "sample2.bed"), sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)

# Create sample annotation CSV
# The 'file' column maps to the BED files in the directory
annot <- data.frame(
    Sample_ID = c("sample1", "sample2"),
    file = c("sample1.bed", "sample2.bed"),
    Sample_Group = c("hiPSC", "other"),
    stringsAsFactors = FALSE
)

write.csv(annot, file = "sample_annotation.csv", row.names = FALSE)