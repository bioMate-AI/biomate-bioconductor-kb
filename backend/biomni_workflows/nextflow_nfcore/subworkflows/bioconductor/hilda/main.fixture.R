library(HiLDA)

# Locate the example Mutation Position Format file shipped with the package
real_input <- system.file("extdata", "esophageal.mp.txt.gz", package="HiLDA")

if (file.exists(real_input)) {
    # Read the gzipped file and write it uncompressed to 'inputFile' as expected by the workflow
    lines <- readLines(gzfile(real_input))
    writeLines(lines, "inputFile")
} else {
    # Fallback to a synthetic dataset matching the Mutation Position Format
    mp_data <- data.frame(
        sample = c("sample1", "sample1", "sample1", "sample2", "sample3"),
        chr = c("chr1", "chr1", "chr2", "chr1", "chr3"),
        pos = c(100, 200, 100, 300, 400),
        ref = c("A", "A", "G", "T", "T"),
        alt = c("C", "T", "T", "C", "C")
    )
    write.table(mp_data, file = "inputFile", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}