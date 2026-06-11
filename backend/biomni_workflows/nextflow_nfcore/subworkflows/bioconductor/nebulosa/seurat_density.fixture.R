library(Matrix)

# Create the directory structure expected by the vignette
dir.create("filtered_gene_bc_matrices/hg19", recursive = TRUE, showWarnings = FALSE)

# Generate a mock sparse matrix
set.seed(42)
mat <- rsparsematrix(50, 100, density = 0.2)
mat <- abs(round(mat * 10))

# Generate mock gene IDs and symbols
# The vignette specifically looks for CD4, CD8A, CCR7, and mitochondrial genes (MT-)
gene_ids <- paste0("ENSG", sprintf("%011d", 1:50))
gene_symbols <- paste0("GENE", 1:50)
gene_symbols[1:5] <- c("CD4", "CD8A", "CCR7", "MT-CO1", "MT-CO2")

rownames(mat) <- gene_ids
colnames(mat) <- paste0("CELL", sprintf("%03d", 1:100))

# Write matrix.mtx
writeMM(mat, "filtered_gene_bc_matrices/hg19/matrix.mtx")

# Write genes.tsv (10X v2 format)
genes_df <- data.frame(ID = gene_ids, Symbol = gene_symbols)
write.table(genes_df, "filtered_gene_bc_matrices/hg19/genes.tsv", 
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Write barcodes.tsv
write.table(data.frame(colnames(mat)), "filtered_gene_bc_matrices/hg19/barcodes.tsv", 
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Create the tar.gz file
tar("pbmc3k_filtered_gene_bc_matrices.tar.gz", files = "filtered_gene_bc_matrices", compression = "gzip")

# Clean up the uncompressed directory to leave only the required input file
unlink("filtered_gene_bc_matrices", recursive = TRUE)