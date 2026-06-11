library(AlpsNMR)

MeOH_plasma_extraction_dir <- system.file("dataset-demo", package = "AlpsNMR")

# 1. dummy_metadata.xlsx
metadata_path <- file.path(MeOH_plasma_extraction_dir, "dummy_metadata.xlsx")
if (file.exists(metadata_path)) {
    file.copy(metadata_path, "dummy_metadata.xlsx", overwrite = TRUE)
}

# 2. zip_files.zip
# The package contains several zip files (e.g., 10.zip, 20.zip) which are zipped Bruker NMR experiment directories.
# We copy the first one to zip_files.zip to satisfy the workflow input requirement.
zip_paths <- list.files(MeOH_plasma_extraction_dir, pattern = "\\.zip$", full.names = TRUE)
if (length(zip_paths) > 0) {
    file.copy(zip_paths[1], "zip_files.zip", overwrite = TRUE)
}