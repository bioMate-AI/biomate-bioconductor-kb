suppressPackageStartupMessages({
    library(celaref)
    library(dplyr)
    library(ggplot2)
    library(illuminaHumanv2.db)
    library(readr)
    library(Matrix)
})

# 1. 10X_pbmc4k (Directory containing 10X cellranger output)
dir.create("10X_pbmc4k/outs/filtered_gene_bc_matrices/GRCh38", recursive = TRUE, showWarnings = FALSE)
dir.create("10X_pbmc4k/outs/analysis/clustering/kmeans_7_clusters", recursive = TRUE, showWarnings = FALSE)

barcodes <- paste0("Cell", 1:50, "-1")
writeLines(barcodes, "10X_pbmc4k/outs/filtered_gene_bc_matrices/GRCh38/barcodes.tsv")

genes <- data.frame(id = paste0("ENSG000000000", 10:59), symbol = paste0("Gene", 1:50))
write.table(genes, "10X_pbmc4k/outs/filtered_gene_bc_matrices/GRCh38/genes.tsv", 
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

mat <- sparseMatrix(
    i = sample(1:50, 200, replace = TRUE), 
    j = sample(1:50, 200, replace = TRUE), 
    x = sample(1:10, 200, replace = TRUE), 
    dims = c(50, 50)
)
writeMM(mat, "10X_pbmc4k/outs/filtered_gene_bc_matrices/GRCh38/matrix.mtx")

clusters <- data.frame(Barcode = barcodes, Cluster = sample(1:7, 50, replace = TRUE))
write.csv(clusters, "10X_pbmc4k/outs/analysis/clustering/kmeans_7_clusters/clusters.csv", 
          row.names = FALSE, quote = FALSE)

# 2. watkins_expression.txt (Normalized microarray expression matrix)
# Using valid Illumina Human v2 probe IDs as expected by the workflow's annotation steps
probes <- head(keys(illuminaHumanv2.db, keytype = "PROBEID"), 100)
expr_mat <- matrix(abs(rnorm(100 * 10, mean = 5, sd = 2)), nrow = 100, ncol = 10)
rownames(expr_mat) <- probes
colnames(expr_mat) <- paste0("Sample", 1:10)

write.table(expr_mat, "watkins_expression.txt", 
            sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)

# 3. watkins_samples.txt (Microarray sample sheet metadata)
samples_df <- data.frame(
    CellId = paste0("Sample", 1:10),
    Cluster = rep(c("Macrophage", "T_cell"), each = 5),
    sample = paste0("Sample", 1:10),
    cell_type = rep(c("Macrophage", "T_cell"), each = 5)
)

write_tsv(samples_df, "watkins_samples.txt")