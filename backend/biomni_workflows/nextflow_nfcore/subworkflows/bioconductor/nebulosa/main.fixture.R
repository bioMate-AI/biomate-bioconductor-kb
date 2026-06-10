suppressPackageStartupMessages({
    library(DropletUtils)
    library(Matrix)
})

set.seed(100)
# Create a mock sparse matrix for 10X Genomics data
# 100 genes, 200 cells
counts_mat <- rsparsematrix(100, 200, density = 0.2)
counts_mat@x <- round(abs(counts_mat@x) * 10)
rownames(counts_mat) <- paste0("ENSG00000", 100000 + 1:100)
colnames(counts_mat) <- paste0("CELL", 1:200, "-1")

gene.id <- rownames(counts_mat)
gene.symbol <- paste0("GENE", 1:100)
# Include some mitochondrial genes for QC steps
gene.symbol[1:5] <- paste0("MT-", 1:5)
# Include genes used in the vignette
gene.symbol[6:8] <- c("CD4", "CD8A", "CCR7")

# Create directory structure expected by the workflow
dir.create("filtered_gene_bc_matrices/hg19", recursive = TRUE)

# Write 10x counts in version 2 format (genes.tsv, barcodes.tsv, matrix.mtx)
write10xCounts("filtered_gene_bc_matrices/hg19", counts_mat, 
               gene.id = gene.id, 
               gene.symbol = gene.symbol, 
               barcodes = colnames(counts_mat), 
               version = "2",
               overwrite = TRUE)

# Compress into the expected tar.gz file
tar("pbmc3k_filtered_gene_bc_matrices.tar.gz", "filtered_gene_bc_matrices", compression = "gzip")

# Clean up the uncompressed directory
unlink("filtered_gene_bc_matrices", recursive = TRUE)