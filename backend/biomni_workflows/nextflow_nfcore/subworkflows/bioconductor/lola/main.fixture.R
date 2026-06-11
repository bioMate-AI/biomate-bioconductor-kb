library(LOLA)
library(GenomicRanges)

# Load the sample data provided by the LOLA package
data("sample_input", package="LOLA")    # Provides 'userSets'
data("sample_universe", package="LOLA") # Provides 'userUniverse'

# Helper function to write a GRanges object to a basic BED file
writeBed <- function(gr, file) {
    df <- data.frame(
        chrom = as.character(seqnames(gr)),
        start = start(gr) - 1, # BED format is 0-based
        end = end(gr)
    )
    write.table(df, file, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
}

# Extract individual GRanges from the userSets GRangesList
if (is(userSets, "GRangesList")) {
    grA <- userSets[[1]]
    grB <- if (length(userSets) > 1) userSets[[2]] else userSets[[1]]
    grC <- if (length(userSets) > 2) userSets[[3]] else userSets[[1]]
} else {
    grA <- userSets
    grB <- userSets
    grC <- userSets
}

# Write the required BED files
writeBed(grA, "setA_100.bed")
writeBed(grB, "setB_100.bed")
writeBed(grC, "setC_100.bed")
writeBed(userUniverse, "activeDHS_universe.bed")