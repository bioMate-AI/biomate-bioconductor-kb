library(ccfindR)
library(Matrix)

dir <- system.file('extdata', package = 'ccfindR')

# The vignette uses the 10x files provided in the package's extdata directory.
# We copy them to the working directory to serve as the declared inputs.
if (file.exists(file.path(dir, 'matrix.mtx')) && 
    file.exists(file.path(dir, 'genes.tsv')) && 
    file.exists(file.path(dir, 'barcodes.tsv'))) {
    
    file.copy(file.path(dir, 'matrix.mtx'), 'matrix.mtx', overwrite = TRUE)
    file.copy(file.path(dir, 'genes.tsv'), 'genes.tsv', overwrite = TRUE)
    file.copy(file.path(dir, 'barcodes.tsv'), 'barcodes.tsv', overwrite = TRUE)
    
} else {
    # Fallback: Construct synthetic 10x files matching the vignette's toy matrix dimensions
    set.seed(1)
    mat <- Matrix(rpois(n = 80, lambda = 2), nrow = 4, ncol = 20, sparse = TRUE)
    writeMM(mat, 'matrix.mtx')
    
    genes <- data.frame(
        ID = paste0("ENSG00000", 1:4),
        Symbol = LETTERS[1:4]
    )
    write.table(genes, 'genes.tsv', sep = '\t', row.names = FALSE, col.names = FALSE, quote = FALSE)
    
    barcodes <- data.frame(
        Barcode = paste0("CELL_", 1:20, "-1")
    )
    write.table(barcodes, 'barcodes.tsv', sep = '\t', row.names = FALSE, col.names = FALSE, quote = FALSE)
}

stopifnot(file.exists('matrix.mtx'))
stopifnot(file.exists('genes.tsv'))
stopifnot(file.exists('barcodes.tsv'))