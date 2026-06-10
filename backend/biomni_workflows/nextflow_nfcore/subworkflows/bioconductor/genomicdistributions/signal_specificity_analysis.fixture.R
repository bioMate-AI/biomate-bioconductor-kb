library(GenomicDistributions)
library(rtracklayer)
library(GenomicRanges)

# 1. Generate queryFile.bed
# Using the exact dataset referenced in the vignette
queryFile_pkg <- system.file("extdata", "vistaEnhancers.bed.gz", package="GenomicDistributions")

if (queryFile_pkg != "" && file.exists(queryFile_pkg)) {
    query <- rtracklayer::import(queryFile_pkg)
    rtracklayer::export(query, "queryFile.bed", format = "bed")
} else {
    # Fallback if the file is missing from the installation
    query <- GRanges(seqnames = "chr1", ranges = IRanges(start = c(1000, 2000), width = 500))
    rtracklayer::export(query, "queryFile.bed", format = "bed")
}

# 2. Generate example_cell_matrix.txt
# The vignette mentions a data matrix with signal values for conditions/cell types.
# Since the exact file is not shipped/documented with a specific path, we construct a synthetic 
# matrix matching the expected format (regions x cell types).
signal_matrix <- data.frame(
    CellType_A = runif(length(query), 0, 50),
    CellType_B = runif(length(query), 0, 50),
    CellType_C = runif(length(query), 0, 50)
)
rownames(signal_matrix) <- paste0("region_", seq_along(query))

write.table(signal_matrix, "example_cell_matrix.txt", sep = "\t", quote = FALSE, col.names = NA)