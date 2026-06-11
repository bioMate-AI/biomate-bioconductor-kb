suppressPackageStartupMessages(library(RnBeads))
suppressPackageStartupMessages(library(RnBeads.hg19))

# Load the example object from the companion package as shown in the vignette
data(small.example.object)

# 1. Generate sample_annotation.csv
# Extract the phenotype/sample annotation table from the example object
annot <- pheno(rnb.set.example)
write.csv(annot, "sample_annotation.csv", row.names = FALSE, quote = FALSE)

# 2. Generate bed
# Create a minimal synthetic BED file to satisfy the 'bed' input requirement
bed_data <- data.frame(
    chrom = c("chr1", "chr2"),
    start = c(10000, 20000),
    end = c(10001, 20001),
    name = c("cg00000001", "cg00000002"),
    score = c(0, 0),
    strand = c("+", "-")
)
write.table(bed_data, "bed", sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)