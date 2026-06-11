library(RegionalST)
library(BayesSpace)
library(Matrix)
library(CARD)

# Load the example dataset from RegionalST
data(example_sce, package = "RegionalST")

# Safeguard for spatial coordinates if they are missing
if(is.null(example_sce$row)) example_sce$row <- sample(1:50, ncol(example_sce), replace=TRUE)
if(is.null(example_sce$col)) example_sce$col <- sample(1:50, ncol(example_sce), replace=TRUE)
if(is.null(example_sce$imagerow)) example_sce$imagerow <- example_sce$row * 10
if(is.null(example_sce$imagecol)) example_sce$imagecol <- example_sce$col * 10

# 1. Create Space Ranger output directory structure
dir.create("path/to/spaceranger/outs/filtered_feature_bc_matrix", recursive = TRUE, showWarnings = FALSE)
dir.create("path/to/spaceranger/outs/spatial", recursive = TRUE, showWarnings = FALSE)

# Write matrix.mtx.gz
counts_mat <- counts(example_sce)
mat_file <- "path/to/spaceranger/outs/filtered_feature_bc_matrix/matrix.mtx"
Matrix::writeMM(counts_mat, mat_file)
zz <- gzfile(paste0(mat_file, ".gz"), "wb")
writeBin(readBin(mat_file, "raw", file.info(mat_file)$size), zz)
close(zz)
unlink(mat_file)

# Write features.tsv.gz
features <- data.frame(
  id = rownames(example_sce),
  name = rownames(example_sce),
  type = "Gene Expression"
)
write.table(features, gzfile("path/to/spaceranger/outs/filtered_feature_bc_matrix/features.tsv.gz"), 
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Write barcodes.tsv.gz
write.table(colnames(example_sce), gzfile("path/to/spaceranger/outs/filtered_feature_bc_matrix/barcodes.tsv.gz"), 
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Write spatial/tissue_positions_list.csv
spatial_pos <- data.frame(
  barcode = colnames(example_sce),
  in_tissue = 1,
  array_row = example_sce$row,
  array_col = example_sce$col,
  pxl_row_in_fullres = example_sce$imagerow,
  pxl_col_in_fullres = example_sce$imagecol
)
write.table(spatial_pos, "path/to/spaceranger/outs/spatial/tissue_positions_list.csv", 
            sep = ",", row.names = FALSE, col.names = FALSE, quote = FALSE)

# Write spatial/scalefactors_json.json
cat('{"tissue_hires_scalef": 1, "tissue_lowres_scalef": 1, "fiducial_diameter_fullres": 1, "spot_diameter_fullres": 1}', 
    file = "path/to/spaceranger/outs/spatial/scalefactors_json.json")

# 2. Create CARD_obj containing cell type proportions
CARD_obj <- new("CARD")
props <- S4Vectors::metadata(example_sce)$Proportions

# Fallback if proportions are missing in the example object
if(is.null(props)) {
    props <- matrix(runif(ncol(example_sce) * 5), ncol = 5)
    props <- props / rowSums(props)
    rownames(props) <- colnames(example_sce)
    colnames(props) <- paste0("CellType", 1:5)
}

CARD_obj@Proportion_CARD <- as.matrix(props)
saveRDS(CARD_obj, "CARD_obj")