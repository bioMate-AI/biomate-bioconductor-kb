library(AlpsNMR)

# Locate the dataset-demo directory shipped with AlpsNMR
MeOH_plasma_extraction_dir <- system.file("dataset-demo", package = "AlpsNMR")

# 1. Provide dummy_metadata.xlsx
metadata_src <- file.path(MeOH_plasma_extraction_dir, "dummy_metadata.xlsx")
if (file.exists(metadata_src)) {
    file.copy(metadata_src, "dummy_metadata.xlsx", overwrite = TRUE)
}

# 2. Provide zip_files.zip
# The package ships several zipped Bruker NMR experiment directories.
# We copy the first one and rename it to "zip_files.zip" to match the expected input file name.
zip_files_orig <- list.files(MeOH_plasma_extraction_dir, pattern = "\\.zip$", full.names = TRUE)
if (length(zip_files_orig) > 0) {
    file.copy(zip_files_orig[1], "zip_files.zip", overwrite = TRUE)
}