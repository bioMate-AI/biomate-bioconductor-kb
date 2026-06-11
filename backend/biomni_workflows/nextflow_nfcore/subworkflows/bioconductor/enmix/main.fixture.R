library(ENmix)
library(minfiData)

# Find the extdata directory in minfiData which contains the example IDAT files
minfi_path <- file.path(find.package("minfiData"), "extdata")

# Create the target directory expected by the workflow
target_dir <- "directory path for idat files"
dir.create(target_dir, showWarnings = FALSE, recursive = TRUE)

# Copy all files (including IDATs and SampleSheet) to the target directory
files_to_copy <- list.files(minfi_path, full.names = TRUE, recursive = TRUE)
for (f in files_to_copy) {
    # Extract relative path to maintain directory structure (e.g., for subfolders containing IDATs)
    rel_path <- substr(f, nchar(minfi_path) + 2, nchar(f))
    dest_file <- file.path(target_dir, rel_path)
    
    # Ensure the destination sub-directory exists
    dir.create(dirname(dest_file), showWarnings = FALSE, recursive = TRUE)
    
    # Copy the file
    file.copy(f, dest_file, overwrite = TRUE)
}