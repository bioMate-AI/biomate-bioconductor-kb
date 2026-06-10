library(flowGate)
library(flowCore)
library(flowWorkspace)

# Create the directory for FCS files
dir.create("path_to_fcs", showWarnings = FALSE)

# Locate FCS files from flowGate or flowCore
fcs_files <- list.files(system.file("extdata", package = "flowGate"), pattern = "\\.FCS$", full.names = TRUE, ignore.case = TRUE)
if (length(fcs_files) == 0) {
    fcs_files <- list.files(system.file("extdata", package = "flowCore"), pattern = "\\.fcs$", full.names = TRUE, ignore.case = TRUE)
}

# Copy files to the target directory, ensuring the .FCS extension is uppercase as expected by the pattern
for (f in fcs_files) {
    dest <- file.path("path_to_fcs", paste0(tools::file_path_sans_ext(basename(f)), ".FCS"))
    file.copy(f, dest)
}

# Locate or create the compensation matrix file
comp_file <- system.file("extdata", "compdata", "compmatrix", package = "flowCore")
if (file.exists(comp_file)) {
    file.copy(comp_file, "compmatrix")
} else {
    # Construct a synthetic compensation matrix matching the expected format (skip = 2, header = TRUE)
    lines <- c(
        "Compensation Matrix",
        "2",
        "FL1-H\tFL2-H\tFL3-H\tFL4-H",
        "1\t0\t0\t0",
        "0\t1\t0\t0",
        "0\t0\t1\t0",
        "0\t0\t0\t1"
    )
    writeLines(lines, "compmatrix")
}