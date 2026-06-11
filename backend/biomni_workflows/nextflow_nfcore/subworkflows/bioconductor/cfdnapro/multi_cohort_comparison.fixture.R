library(cfDNAPro)

# Get the path to example data in cfDNAPro package library path
example_data_path <- examplePath("groups_picard")

# Create the target directory
dir.create("data_path", showWarnings = FALSE, recursive = TRUE)

# Copy the contents of the example data directory to data_path
files_to_copy <- list.files(example_data_path, full.names = TRUE)
file.copy(files_to_copy, "data_path", recursive = TRUE)