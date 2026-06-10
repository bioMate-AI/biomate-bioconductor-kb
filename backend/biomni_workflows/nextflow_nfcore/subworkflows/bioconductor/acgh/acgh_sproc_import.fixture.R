library(aCGH)

datadir <- system.file("examples", package = "aCGH")

# Copy sproc files to the working directory
sproc_files <- list.files(path = datadir, pattern = "sproc", full.names = TRUE)
if (length(sproc_files) > 0) {
    file.copy(sproc_files, ".", overwrite = TRUE)
} else {
    # Fallback dummy creation if files are missing from the installation
    dummy_sproc <- data.frame(
        Clone = paste0("Clone", 1:10),
        LogRatio = rnorm(10)
    )
    write.table(dummy_sproc, "sproc1.txt", sep = "\t", row.names = FALSE, quote = FALSE)
    write.table(dummy_sproc, "sproc2.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}

# Copy the clone mapping file to the working directory
mapping_file <- file.path(datadir, "human.clones.info.Jul03.txt")
if (file.exists(mapping_file)) {
    file.copy(mapping_file, "human.clones.info.Jul03.txt", overwrite = TRUE)
} else {
    # Fallback dummy creation if file is missing from the installation
    dummy_mapping <- data.frame(
        Clone = paste0("Clone", 1:10),
        Chrom = rep(1:2, 5),
        kb = seq(1000, 10000, by = 1000)
    )
    write.table(dummy_mapping, "human.clones.info.Jul03.txt", sep = "\t", row.names = FALSE, quote = FALSE)
}