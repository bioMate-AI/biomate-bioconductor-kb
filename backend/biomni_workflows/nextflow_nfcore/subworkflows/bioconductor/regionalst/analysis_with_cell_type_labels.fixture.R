library(RegionalST)
library(SingleCellExperiment)
library(DropletUtils)

# Load the example dataset provided by the package
data("example_sce", package = "RegionalST")

# 1. Create Space Ranger output directory structure
out_dir <- "path/to/spaceranger/outs"
mat_dir <- file.path(out_dir, "filtered_feature_bc_matrix")
spatial_dir <- file.path(out_dir, "spatial")

dir.create(mat_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(spatial_dir, recursive = TRUE, showWarnings = FALSE)

# Write the count matrix in 10x format
write10xCounts(mat_dir, counts(example_sce), type = "sparse", version = "3", overwrite = TRUE)

# Extract or mock spatial coordinates
array_row <- if (!is.null(example_sce$row)) example_sce$row else sample(1:50, ncol(example_sce), replace=TRUE)
array_col <- if (!is.null(example_sce$col)) example_sce$col else sample(1:50, ncol(example_sce), replace=TRUE)
pxl_row <- if (!is.null(example_sce$imagerow)) example_sce$imagerow else array_row * 10
pxl_col <- if (!is.null(example_sce$imagecol)) example_sce$imagecol else array_col * 10

pos <- data.frame(
    barcode = colnames(example_sce),
    in_tissue = 1,
    array_row = array_row,
    array_col = array_col,
    pxl_row_in_fullres = pxl_row,
    pxl_col_in_fullres = pxl_col
)

# Write spatial coordinates (both Space Ranger < 2.0 and >= 2.0 formats for compatibility)
write.table(pos, file.path(spatial_dir, "tissue_positions_list.csv"), sep = ",", row.names = FALSE, col.names = FALSE, quote = FALSE)
write.table(pos, file.path(spatial_dir, "tissue_positions.csv"), sep = ",", row.names = FALSE, col.names = TRUE, quote = FALSE)

# Write scalefactors JSON
cat('{"tissue_hires_scalef": 0.1, "tissue_lowres_scalef": 0.03, "fiducial_diameter_fullres": 100, "spot_diameter_fullres": 50}', 
    file = file.path(spatial_dir, "scalefactors_json.json"))

# 2. Write cell_type_labels
celltype <- if (!is.null(example_sce$celltype)) example_sce$celltype else sample(c("Cancer Epithelial", "CAFs", "T-cells"), ncol(example_sce), replace=TRUE)
cell_type_df <- data.frame(
    barcode = colnames(example_sce),
    celltype = celltype
)
write.csv(cell_type_df, "cell_type_labels", row.names = FALSE, quote = FALSE)