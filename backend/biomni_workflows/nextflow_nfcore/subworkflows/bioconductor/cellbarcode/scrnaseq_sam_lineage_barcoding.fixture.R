library(CellBarcode)

sam_file_pkg <- system.file("extdata", "scRNASeq_10X.sam", package = "CellBarcode")

if (file.exists(sam_file_pkg)) {
    file.copy(sam_file_pkg, "sam_file", overwrite = TRUE)
} else {
    # Fallback to a minimal synthetic SAM file matching the vignette's pattern and tags
    sam_content <- c(
        "@HD\tVN:1.5\tSO:coordinate",
        "@SQ\tSN:chr1\tLN:248956422",
        "read1\t0\tchr1\t100\t255\t18M\t*\t0\t0\tAGATCAGATCGTGTGGTA\t*\tCR:Z:AAGCAGTGGTATCAAC\tUR:Z:ACGT"
    )
    writeLines(sam_content, "sam_file")
}