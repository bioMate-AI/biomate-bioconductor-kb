library(celaref)

set.seed(123)

# 1. Generate query counts matrix (counts_filepath.query)
genes <- paste0("Gene", 1:200)
cells <- paste0("Cell", 1:100)
counts <- matrix(rpois(200 * 100, lambda = 2), nrow = 200, ncol = 100)
rownames(counts) <- genes
colnames(counts) <- cells
write.table(counts, file = "counts_filepath.query", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)

# 2. Generate query cell metadata (cell_info_filepath.query)
cell_info <- data.frame(
    CellId = cells, 
    Cluster = paste0("Cluster", sample(1:4, 100, replace = TRUE))
)
write.table(cell_info, file = "cell_info_filepath.query", sep = "\t", quote = FALSE, row.names = FALSE)

# 3. Generate normalized microarray expression matrix (norm_expression_file)
samples <- paste0("Sample", 1:20)
exprs <- matrix(rnorm(200 * 20, mean = 8, sd = 2), nrow = 200, ncol = 20)
rownames(exprs) <- genes
colnames(exprs) <- samples
write.table(exprs, file = "norm_expression_file", sep = "\t", quote = FALSE, row.names = TRUE, col.names = NA)

# 4. Generate microarray sample sheet (samples_file)
samples_info <- data.frame(
    SampleId = samples, 
    Cluster = paste0("RefGroup", sample(1:3, 20, replace = TRUE))
)
write.table(samples_info, file = "samples_file", sep = "\t", quote = FALSE, row.names = FALSE)