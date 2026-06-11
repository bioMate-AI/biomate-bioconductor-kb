library(DiffBind)

# Create directory for peak files
dir.create("peaks", showWarnings = FALSE, recursive = TRUE)

# Construct a synthetic BED file for the peak caller output
peak_data <- data.frame(
    chr = c("chr1", "chr1", "chr2"),
    start = c(10000, 20000, 30000),
    end = c(10500, 20500, 30500),
    name = c("peak1", "peak2", "peak3"),
    score = c(10, 20, 30)
)

# Write and compress the BED file
gz1 <- gzfile("peaks/BT474_ER_1.bed.gz", "w")
write.table(peak_data, file = gz1, sep = "\t", quote = FALSE, row.names = FALSE, col.names = FALSE)
close(gz1)

# Construct a synthetic sample sheet metadata file
samples <- data.frame(
    SampleID = "BT474_ER_1",
    Tissue = "BT474",
    Factor = "ER",
    Condition = "Responsive",
    Treatment = "FullMedia",
    Replicate = 1,
    bamReads = NA,
    ControlID = NA,
    bamControl = NA,
    Peaks = "peaks/BT474_ER_1.bed.gz",
    PeakCaller = "bed"
)

# Write the sample sheet to the working directory
write.csv(samples, "tamoxifen.csv", row.names = FALSE)