library(GOTHiC)

# Attempt to use the companion data package as shown in the vignette
if (require("HiCDataLymphoblast", character.only = TRUE, quietly = TRUE)) {
    dirPath <- system.file("extdata", package = "HiCDataLymphoblast")
    files <- list.files(dirPath, full.names = TRUE)
    if (length(files) >= 2) {
        file.copy(files[1], "fileName1", overwrite = TRUE)
        file.copy(files[2], "fileName2", overwrite = TRUE)
    }
}

# Fallback to synthetic data if the companion package is unavailable
if (!file.exists("fileName1") || !file.exists("fileName2")) {
    # Create dummy tabular files compatible with pairReads(..., fileType="Table")
    # Format typically expects: read_id, strand, chr, position, sequence, quality, etc.
    dummy1 <- data.frame(
        id = c("read1", "read2", "read3"),
        strand = c("+", "+", "-"),
        chr = c("chr20", "chr20", "chr20"),
        pos = c(1000000, 1500000, 2000000),
        seq = c("ACGT", "TGCA", "GATC"),
        qual = c("IIII", "IIII", "IIII"),
        mapq = c(255, 255, 255)
    )
    
    dummy2 <- data.frame(
        id = c("read1", "read2", "read3"),
        strand = c("-", "-", "+"),
        chr = c("chr20", "chr20", "chr20"),
        pos = c(1005000, 1505000, 2005000),
        seq = c("ACGT", "TGCA", "GATC"),
        qual = c("IIII", "IIII", "IIII"),
        mapq = c(255, 255, 255)
    )
    
    write.table(dummy1, "fileName1", row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")
    write.table(dummy2, "fileName2", row.names = FALSE, col.names = FALSE, quote = FALSE, sep = "\t")
}