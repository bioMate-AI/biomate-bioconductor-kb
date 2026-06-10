# [biomate-fx-deps] self-install the fixture's declared packages (real example data) on a clean runtime
.fx_deps <- c("SingleCellExperiment", "Matrix", "BayesSpace")
.fx_miss <- .fx_deps[!vapply(.fx_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
if (length(.fx_miss)) {
  if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
  bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
  suppressMessages(tryCatch(BiocManager::install(.fx_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.fx_miss, update=FALSE, ask=FALSE)))
}
library(SingleCellExperiment)
library(Matrix)
library(BayesSpace)

# Set seed for reproducibility
set.seed(123)

# Define dimensions for the synthetic dataset
n_genes <- 50
n_spots <- 64

# Generate synthetic counts matrix
counts_mat <- matrix(rpois(n_genes * n_spots, lambda = 5), nrow = n_genes, ncol = n_spots)
rownames(counts_mat) <- paste0("Gene", 1:n_genes)
colnames(counts_mat) <- paste0("Spot", 1:n_spots)

# Generate rowData
rowData <- data.frame(
    gene_id = rownames(counts_mat),
    gene_name = rownames(counts_mat),
    stringsAsFactors = FALSE
)

# Generate colData with array_row and array_col
colData <- data.frame(
    array_row = rep(1:8, 8),
    array_col = rep(1:8, each = 8),
    stringsAsFactors = FALSE
)
rownames(colData) <- colnames(counts_mat)

# 1. Write rowData.csv
write.csv(rowData, "rowData.csv", row.names = FALSE, quote = FALSE)

# 2. Write colData.csv
write.csv(colData, "colData.csv", row.names = TRUE, quote = FALSE)

# 3. Write counts.csv.gz
gz_counts <- gzfile("counts.csv.gz", "w")
write.csv(counts_mat, gz_counts, row.names = TRUE, quote = FALSE)
close(gz_counts)

# 4. Create spaceranger_outs/ directory structure
dir.create("spaceranger_outs/spatial", recursive = TRUE, showWarnings = FALSE)
dir.create("spaceranger_outs/filtered_feature_bc_matrix", recursive = TRUE, showWarnings = FALSE)

# Write spatial/tissue_positions_list.csv (Space Ranger 1.x format, no header)
tissue_positions <- data.frame(
    barcode = colnames(counts_mat),
    in_tissue = 1,
    array_row = colData$array_row,
    array_col = colData$array_col,
    pxl_row_in_fullres = colData$array_row * 100,
    pxl_col_in_fullres = colData$array_col * 100
)
write.table(tissue_positions, "spaceranger_outs/spatial/tissue_positions_list.csv", 
            sep = ",", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Write spatial/scalefactors_json.json
cat('{"tissue_hires_scalef": 0.1, "tissue_lowres_scalef": 0.03, "fiducial_diameter_fullres": 100, "spot_diameter_fullres": 50}', 
    file = "spaceranger_outs/spatial/scalefactors_json.json")

# Create dummy images to satisfy readVisium image checks
png("spaceranger_outs/spatial/tissue_hires_image.png", width = 10, height = 10)
plot.new()
dev.off()

png("spaceranger_outs/spatial/tissue_lowres_image.png", width = 10, height = 10)
plot.new()
dev.off()

# Write filtered_feature_bc_matrix/ files
mat <- Matrix(counts_mat, sparse = TRUE)

# barcodes.tsv.gz
gz_barcodes <- gzfile("spaceranger_outs/filtered_feature_bc_matrix/barcodes.tsv.gz", "w")
write.table(colnames(counts_mat), gz_barcodes, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
close(gz_barcodes)

# features.tsv.gz
features <- data.frame(
    id = rownames(counts_mat),
    name = rownames(counts_mat),
    type = "Gene Expression"
)
gz_features <- gzfile("spaceranger_outs/filtered_feature_bc_matrix/features.tsv.gz", "w")
write.table(features, gz_features, sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)
close(gz_features)

# matrix.mtx.gz
Matrix::writeMM(mat, "spaceranger_outs/filtered_feature_bc_matrix/matrix.mtx")
lines <- readLines("spaceranger_outs/filtered_feature_bc_matrix/matrix.mtx")
gz_matrix <- gzfile("spaceranger_outs/filtered_feature_bc_matrix/matrix.mtx.gz", "w")
writeLines(lines, gz_matrix)
close(gz_matrix)
file.remove("spaceranger_outs/filtered_feature_bc_matrix/matrix.mtx")