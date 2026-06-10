library(SpotClean)
library(DropletUtils)

# Define output directories
out_dir <- "/path/to/spaceranger/output/"
raw_dir <- file.path(out_dir, "raw_feature_bc_matrix")
spatial_out <- file.path(out_dir, "spatial")

# Create directories
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(spatial_out, recursive = TRUE, showWarnings = FALSE)

# Load the built-in example count matrix
data("mbrain_raw", package = "SpotClean")

# Write the 10x raw feature-barcode matrix
write10xCounts(
    path = raw_dir, 
    x = mbrain_raw, 
    gene.id = rownames(mbrain_raw), 
    gene.symbol = rownames(mbrain_raw), 
    version = "3", 
    overwrite = TRUE
)

# Locate and copy the spatial metadata files shipped with SpotClean
spatial_dir <- system.file("extdata", "V1_Adult_Mouse_Brain_spatial", package = "SpotClean")
spatial_files <- list.files(spatial_dir, full.names = TRUE)
file.copy(spatial_files, spatial_out, recursive = TRUE)