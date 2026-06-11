suppressPackageStartupMessages({
    library(RegionalST)
    library(SingleCellExperiment)
    library(Matrix)
    library(DropletUtils)
})

# Load the example dataset provided by the package
data("example_sce", package = "RegionalST")

# Define the target directory as specified in the ground truth
outdir <- "/Users/zli16/Dropbox/TrySTData/Ovarian_10x"
dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

# 1. Create the filtered_feature_bc_matrix directory and files
mat_dir <- file.path(outdir, "filtered_feature_bc_matrix")
unlink(mat_dir, recursive = TRUE) # Ensure clean state for write10xCounts

counts_mat <- counts(example_sce)
if (is.null(rownames(counts_mat))) rownames(counts_mat) <- paste0("Gene", seq_len(nrow(counts_mat)))
if (is.null(colnames(counts_mat))) colnames(counts_mat) <- paste0("Cell", seq_len(ncol(counts_mat)))

# Write the count matrix in 10x format
DropletUtils::write10xCounts(mat_dir, counts_mat, type = "sparse", version = "3")

# 2. Create the spatial directory and files
spatial_dir <- file.path(outdir, "spatial")
dir.create(spatial_dir, recursive = TRUE, showWarnings = FALSE)

# Construct the tissue_positions_list.csv expected by BayesSpace::readVisium
pos <- data.frame(
    barcode = colnames(counts_mat),
    in_tissue = 1,
    array_row = if (!is.null(example_sce$row)) example_sce$row else seq_len(ncol(counts_mat)),
    array_col = if (!is.null(example_sce$col)) example_sce$col else seq_len(ncol(counts_mat)),
    pxl_row_in_fullres = if (!is.null(example_sce$imagerow)) example_sce$imagerow else seq_len(ncol(counts_mat)),
    pxl_col_in_fullres = if (!is.null(example_sce$imagecol)) example_sce$imagecol else seq_len(ncol(counts_mat))
)

write.table(
    pos, 
    file.path(spatial_dir, "tissue_positions_list.csv"), 
    sep = ",", 
    row.names = FALSE, 
    col.names = FALSE, 
    quote = FALSE
)

# Construct the scalefactors_json.json expected by BayesSpace::readVisium
scalefactors <- '{
    "tissue_hires_scalef": 1, 
    "tissue_lowres_scalef": 1, 
    "fiducial_diameter_fullres": 1, 
    "spot_diameter_fullres": 1
}'
writeLines(scalefactors, file.path(spatial_dir, "scalefactors_json.json"))