suppressPackageStartupMessages({
    library(flowGate)
    library(flowCore)
})

# 1. Prepare path_to_fcs directory and copy .FCS files
dir.create("path_to_fcs", showWarnings = FALSE)

fcs_dir <- system.file("extdata", package = "flowGate")
fcs_files <- list.files(fcs_dir, pattern = "\\.FCS$", ignore.case = TRUE, full.names = TRUE)

# Fallback to flowCore if flowGate doesn't have the expected FCS files
if (length(fcs_files) == 0) {
    fcs_dir <- system.file("extdata", package = "flowCore")
    fcs_files <- list.files(fcs_dir, pattern = "\\.fcs$", ignore.case = TRUE, full.names = TRUE)
}

file.copy(fcs_files, "path_to_fcs")

# 2. Prepare compmatrix file
comp_file <- system.file("extdata", "compdata", "compmatrix", package = "flowCore")

if (file.exists(comp_file)) {
    file.copy(comp_file, "compmatrix")
} else {
    # Fallback synthetic compmatrix matching the expected format (header=TRUE, skip=2)
    comp_lines <- c(
        "Cytometer: Synthetic",
        "Date: 2023-01-01",
        "FL1-H\tFL2-H\tFL3-H\tFL4-H",
        "1\t0.24\t0\t0",
        "0.07\t1\t0.08\t0",
        "0\t0.27\t1\t0.16",
        "0\t0\t0.01\t1"
    )
    writeLines(comp_lines, "compmatrix")
}