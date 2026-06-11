library(ChIPComp)

# Locate the extdata directory where the package ships its example files
extdata_dir <- system.file("extdata", package = "ChIPComp")

# Copy all .bed files (IP reads, control reads, and peaks) to the working directory
bed_files <- list.files(extdata_dir, pattern = "\\.bed$", full.names = TRUE)
file.copy(bed_files, ".", overwrite = TRUE)

# Construct the conf.csv file with sample metadata and local file paths
conf <- data.frame(
    SampleID = 1:4,
    condition = c("Helas3", "Helas3", "K562", "K562"),
    factor = c("H3k27ac", "H3k27ac", "H3k27ac", "H3k27ac"),
    ipReads = c("Helas3.ip1.bed", "Helas3.ip2.bed", "K562.ip1.bed", "K562.ip2.bed"),
    ctReads = c("Helas3.ct.bed", "Helas3.ct.bed", "K562.ct.bed", "K562.ct.bed"),
    peaks = c("Helas3.peak.bed", "Helas3.peak.bed", "K562.peak.bed", "K562.peak.bed")
)

# Write the configuration to conf.csv as expected by the workflow
write.csv(conf, "conf.csv", row.names = FALSE, quote = FALSE)