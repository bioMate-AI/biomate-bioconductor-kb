library(SpotClean)
library(Matrix)

# Load the built-in example count matrix
data(mbrain_raw, package = "SpotClean")

# 1. Create raw_feature_bc_matrix directory and its contents
dir.create("raw_feature_bc_matrix", showWarnings = FALSE)

# Write barcodes.tsv.gz
z_barcodes <- gzfile("raw_feature_bc_matrix/barcodes.tsv.gz", "w")
write.table(colnames(mbrain_raw), file = z_barcodes, quote = FALSE, row.names = FALSE, col.names = FALSE)
close(z_barcodes)

# Write features.tsv.gz (10x format typically expects 3 columns: gene_id, gene_name, feature_type)
z_features <- gzfile("raw_feature_bc_matrix/features.tsv.gz", "w")
features <- data.frame(
    V1 = rownames(mbrain_raw), 
    V2 = rownames(mbrain_raw), 
    V3 = "Gene Expression"
)
write.table(features, file = z_features, quote = FALSE, row.names = FALSE, col.names = FALSE, sep = "\t")
close(z_features)

# Write matrix.mtx.gz
writeMM(mbrain_raw, file = "raw_feature_bc_matrix/matrix.mtx")
mtx_lines <- readLines("raw_feature_bc_matrix/matrix.mtx")
z_mtx <- gzfile("raw_feature_bc_matrix/matrix.mtx.gz", "w")
writeLines(mtx_lines, z_mtx)
close(z_mtx)
unlink("raw_feature_bc_matrix/matrix.mtx")

# 2. Copy spatial metadata files from the package's extdata
spatial_dir <- system.file("extdata", "V1_Adult_Mouse_Brain_spatial", package = "SpotClean")

file.copy(
    from = file.path(spatial_dir, "tissue_positions_list.csv"), 
    to = "tissue_positions_list.csv", 
    overwrite = TRUE
)

file.copy(
    from = file.path(spatial_dir, "tissue_lowres_image.png"), 
    to = "tissue_lowres_image.png", 
    overwrite = TRUE
)

file.copy(
    from = file.path(spatial_dir, "scalefactors_json.json"), 
    to = "scalefactors_json.json", 
    overwrite = TRUE
)