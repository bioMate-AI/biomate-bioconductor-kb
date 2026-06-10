library(ccfindR)
library(Matrix)

# Attempt to use the package's own extdata files if they exist
ext_dir <- system.file('extdata', package = 'ccfindR')
mtx_file <- file.path(ext_dir, 'matrix.mtx')
genes_file <- file.path(ext_dir, 'genes.tsv')
barcodes_file <- file.path(ext_dir, 'barcodes.tsv')

if (file.exists(mtx_file) && file.exists(genes_file) && file.exists(barcodes_file)) {
    file.copy(mtx_file, 'matrix.mtx', overwrite = TRUE)
    file.copy(genes_file, 'genes.tsv', overwrite = TRUE)
    file.copy(barcodes_file, 'barcodes.tsv', overwrite = TRUE)
} else {
    # Fallback: Generate synthetic 10x Genomics format files
    set.seed(1)
    
    # Create a toy count matrix
    n_genes <- 50
    n_cells <- 20
    mat <- matrix(rpois(n = n_genes * n_cells, lambda = 2), nrow = n_genes, ncol = n_cells)
    
    # Generate mock Ensembl IDs, Gene Symbols, and Cell Barcodes
    genes_id <- paste0("ENSG", sprintf("%011d", 1:n_genes))
    genes_sym <- paste0("GENE", 1:n_genes)
    barcodes <- paste0("CELL", sprintf("%03d", 1:n_cells), "-1")
    
    rownames(mat) <- genes_id
    colnames(mat) <- barcodes
    
    # Write matrix.mtx (MatrixMarket format)
    sp_mat <- Matrix::Matrix(mat, sparse = TRUE)
    Matrix::writeMM(sp_mat, file = "matrix.mtx")
    
    # Write genes.tsv (no header, 2 columns: ID and Symbol)
    genes_df <- data.frame(V1 = genes_id, V2 = genes_sym, stringsAsFactors = FALSE)
    write.table(genes_df, file = "genes.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    # Write barcodes.tsv (no header, 1 column: Barcode)
    barcodes_df <- data.frame(V1 = barcodes, stringsAsFactors = FALSE)
    write.table(barcodes_df, file = "barcodes.tsv", sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
}