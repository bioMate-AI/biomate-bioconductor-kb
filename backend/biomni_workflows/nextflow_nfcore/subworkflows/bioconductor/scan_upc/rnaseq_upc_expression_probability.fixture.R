suppressPackageStartupMessages({
    library(scan_upc)
})

# Construct a small synthetic file that matches the expected format
# (tab-delimited file containing RPKM or FPKM expression values)
set.seed(123)
rpkm_matrix <- matrix(
    runif(200, min = 0, max = 100), 
    nrow = 50, 
    ncol = 4, 
    dimnames = list(
        paste0("Gene", 1:50), 
        paste0("Sample", 1:4)
    )
)

write.table(
    rpkm_matrix, 
    file = "rna_seq_rpkm.txt", 
    sep = "\t", 
    quote = FALSE, 
    row.names = TRUE, 
    col.names = NA
)