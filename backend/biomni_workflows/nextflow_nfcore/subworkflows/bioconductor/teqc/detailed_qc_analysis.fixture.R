library(TEQC)

exptPath <- system.file("extdata", package = "TEQC")

# 1. ExampleSet_Targets.bed
targets_file <- file.path(exptPath, "ExampleSet_Targets.bed")
if (file.exists(targets_file)) {
    file.copy(targets_file, "ExampleSet_Targets.bed", overwrite = TRUE)
} else {
    targets_data <- data.frame(
        chr = c("chr1", "chr1", "chr2"),
        start = c(1000, 2000, 3000),
        end = c(1500, 2500, 3500)
    )
    write.table(targets_data, "ExampleSet_Targets.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# 2. ExampleSet_Reads.bed
reads_file <- file.path(exptPath, "ExampleSet_Reads.bed")
if (file.exists(reads_file)) {
    file.copy(reads_file, "ExampleSet_Reads.bed", overwrite = TRUE)
} else {
    reads_data <- data.frame(
        chr = c("chr1", "chr1", "chr2", "chr2", "chr1"),
        start = c(1010, 1050, 3010, 3050, 2010),
        end = c(1060, 1100, 3060, 3100, 2060),
        id = c("read1", "read1", "read2", "read2", "read3")
    )
    write.table(reads_data, "ExampleSet_Reads.bed", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# 3. ExampleSet_Baits.txt
baits_file <- file.path(exptPath, "ExampleSet_Baits.txt")
if (file.exists(baits_file)) {
    file.copy(baits_file, "ExampleSet_Baits.txt", overwrite = TRUE)
} else {
    baits_data <- data.frame(
        col1 = c("bait1", "bait2", "bait3"),
        seq = c("ATGC", "CGTA", "GCTA"),
        chr = c("chr1", "chr1", "chr2"),
        start = c(1000, 2000, 3000),
        end = c(1100, 2100, 3100)
    )
    write.table(baits_data, "ExampleSet_Baits.txt", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}