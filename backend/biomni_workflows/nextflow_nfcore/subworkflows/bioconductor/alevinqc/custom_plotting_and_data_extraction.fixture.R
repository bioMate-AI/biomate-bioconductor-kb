library(alevinQC)

# Locate the example Alevin output directory shipped with the package
example_dir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")

# Fallback in case the specific version directory is renamed in newer package versions
if (example_dir == "") {
    example_dirs <- list.files(system.file("extdata", package = "alevinQC"), 
                               pattern = "alevin_example", full.names = TRUE)
    if (length(example_dirs) > 0) {
        example_dir <- example_dirs[1]
    }
}

# Create the expected input directory in the working directory
dir.create("baseDir", showWarnings = FALSE)

# Copy the Alevin output structure (alevin/, aux_info/, cmd_info.json) into baseDir
file.copy(list.files(example_dir, full.names = TRUE), "baseDir", recursive = TRUE)