library(snpStats)

# Load the example dataset from the package
data(ld.example)

# Serialize the SnpMatrix object
saveRDS(ceph.1mb, "ceph.1mb")

# Handle potential case differences in the column name and serialize the numeric vector
if (is.null(support.ld$Position) && !is.null(support.ld$position)) {
    support.ld$Position <- support.ld$position
} else if (is.null(support.ld$Position)) {
    # Fallback if neither exists, though ld.example should contain it
    support.ld$Position <- 1:ncol(ceph.1mb)
}

saveRDS(support.ld$Position, "support.ld$Position")