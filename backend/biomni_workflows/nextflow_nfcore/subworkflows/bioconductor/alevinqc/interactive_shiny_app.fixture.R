library(alevinQC)

# Locate the example Alevin output directory shipped with the package
example_dir <- system.file("extdata/alevin_example_v0.14", package = "alevinQC")

# Fallback to any available alevin_example directory if v0.14 is not found
if (!file.exists(example_dir) || example_dir == "") {
    example_dir <- list.files(system.file("extdata", package = "alevinQC"), 
                              pattern = "alevin_example", 
                              full.names = TRUE)[1]
}

# Create the expected input directory in the working directory
dir.create("baseDir", showWarnings = FALSE)

# Copy the contents (alevin/, aux_info/, cmd_info.json) into baseDir
file.copy(list.files(example_dir, full.names = TRUE), "baseDir", recursive = TRUE)