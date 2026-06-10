suppressPackageStartupMessages({
  library(CNVPanelizer)
  library(Rsamtools)
})

# 1. Create BED file defining the amplicons
# The vignette uses column 4 for amplicon names, split by "_"
bed_content <- data.frame(
  chrom = c("chr1", "chr1", "chr2"),
  chromStart = c(1000, 2000, 3000),
  chromEnd = c(1100, 2100, 3100),
  name = c("Gene1_Amplicon1", "Gene1_Amplicon2", "Gene2_Amplicon1"),
  score = c(0, 0, 0),
  strand = c("+", "+", "-")
)
write.table(bed_content, "someFile.bed", sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)

# 2. Create synthetic SAM files and convert them to BAM files for samples and references
dir.create("sampleDirectory", showWarnings = FALSE)
dir.create("referenceDirectory", showWarnings = FALSE)

# Synthetic SAM content matching the BED coordinates
sam_lines <- c(
  "@HD\tVN:1.4\tSO:unsorted",
  "@SQ\tSN:chr1\tLN:10000",
  "@SQ\tSN:chr2\tLN:10000",
  "r1\t0\tchr1\t1010\t60\t50M\t*\t0\t0\tACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGAC\tIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII",
  "r2\t0\tchr1\t2010\t60\t50M\t*\t0\t0\tACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGAC\tIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII",
  "r3\t16\tchr2\t3010\t60\t50M\t*\t0\t0\tACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGACTGAC\tIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII"
)

# Write and convert sample BAM
writeLines(sam_lines, "sampleDirectory/sample1.sam")
asBam("sampleDirectory/sample1.sam", destination = "sampleDirectory/sample1")
unlink("sampleDirectory/sample1.sam")

# Write and convert reference BAM
writeLines(sam_lines, "referenceDirectory/ref1.sam")
asBam("referenceDirectory/ref1.sam", destination = "referenceDirectory/ref1")
unlink("referenceDirectory/ref1.sam")