library(mBPCR)

ext_file <- system.file("extdata", "rec10k.txt", package = "mBPCR")

if (ext_file != "" && file.exists(ext_file)) {
    file.copy(ext_file, "rec10k.txt", overwrite = TRUE)
} else {
    data(rec10k, package = "mBPCR")
    # Create a file with a dummy first line to be skipped by NRowSkip=1
    cat("Dummy header line to be skipped\n", file = "rec10k.txt")
    write.table(rec10k, "rec10k.txt", sep = "\t", row.names = FALSE, col.names = TRUE, quote = FALSE, append = TRUE)
}