library(ccfindR)
library(Matrix)

extdata_dir <- system.file("extdata", package = "ccfindR")

# matrix.mtx
matrix_file <- file.path(extdata_dir, "matrix.mtx")
if (file.exists(matrix_file)) {
    file.copy(matrix_file, "matrix.mtx", overwrite = TRUE)
} else {
    mat <- Matrix(rpois(100, 2), nrow = 10, ncol = 10, sparse = TRUE)
    writeMM(mat, "matrix.mtx")
}

# genes.tsv
genes_file <- file.path(extdata_dir, "genes.tsv")
if (file.exists(genes_file)) {
    file.copy(genes_file, "genes.tsv", overwrite = TRUE)
} else {
    genes <- data.frame(
        V1 = paste0("ENSG00000", 1:10),
        V2 = paste0("Gene", 1:10)
    )
    write.table(genes, "genes.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}

# barcodes.tsv
barcodes_file <- file.path(extdata_dir, "barcodes.tsv")
if (file.exists(barcodes_file)) {
    file.copy(barcodes_file, "barcodes.tsv", overwrite = TRUE)
} else {
    barcodes <- data.frame(
        V1 = paste0("CELL", 1:10, "-1")
    )
    write.table(barcodes, "barcodes.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}