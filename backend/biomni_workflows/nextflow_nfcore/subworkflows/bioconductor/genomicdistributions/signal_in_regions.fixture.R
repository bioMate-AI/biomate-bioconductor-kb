library(GenomicDistributions)
library(rtracklayer)
library(data.table)

# 1. vistaEnhancers.bed.gz
# The vignette uses a file shipped with the package. We copy it to the working directory.
queryFile <- system.file("extdata", "vistaEnhancers.bed.gz", package="GenomicDistributions")
if (file.exists(queryFile)) {
    file.copy(queryFile, "vistaEnhancers.bed.gz", overwrite = TRUE)
} else {
    # Fallback if the file is not found in the installation
    gr <- GRanges(seqnames = "chr1", ranges = IRanges(start = seq(1000, 10000, by = 1000), width = 500))
    export(gr, "vistaEnhancers.bed.gz", format = "bed")
}

# 2. example_cell_matrix.txt
# The vignette mentions a data matrix with signal values for conditions of interest.
# We construct a synthetic matrix matching the expected format (regions x conditions).
cell_matrix <- data.table(
    chr = rep("chr1", 10),
    start = seq(1000, 10000, by = 1000),
    end = seq(1499, 10499, by = 1000),
    CellTypeA = runif(10, 0, 50),
    CellTypeB = runif(10, 0, 50),
    CellTypeC = runif(10, 0, 50)
)
fwrite(cell_matrix, "example_cell_matrix.txt", sep = "\t")