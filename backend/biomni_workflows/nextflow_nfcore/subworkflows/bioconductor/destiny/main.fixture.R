# Load required packages
suppressPackageStartupMessages({
    library(destiny)
    library(Biobase)
})

# 1. Reproduce the data-preparation logic to materialize the example objects
# The vignette uses the 'guo' dataset shipped with destiny.
data(guo, package = "destiny")

# Reconstruct the 'raw_ct' data.frame that would have been read from mmc4.xls
# exprs(guo) is a genes x cells matrix. We need to transpose it.
raw_ct <- as.data.frame(t(exprs(guo)))

# The vignette extracts 'num_cells' from the 'Cell' column using:
# gsub('^(\\d+)C.*$', '\\1', ct$Cell)
# We reconstruct the 'Cell' column to match this expected format (e.g., "1C 1", "2C 1")
cell_counts <- pData(guo)$num_cells
cell_ids <- ave(cell_counts, cell_counts, FUN = seq_along)
raw_ct$Cell <- paste0(cell_counts, "C ", cell_ids)

# Ensure 'Cell' is the first column as expected by the workflow
raw_ct <- raw_ct[, c("Cell", setdiff(names(raw_ct), "Cell"))]

# Reconstruct the 'dilutions' data.frame that would have been read from mmc6.xls
# The vignette mentions 2