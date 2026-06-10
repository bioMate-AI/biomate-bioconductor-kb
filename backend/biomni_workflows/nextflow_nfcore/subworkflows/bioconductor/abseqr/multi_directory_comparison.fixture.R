library(abseqR)

# Locate the example data provided by the abseqR package
exdata <- system.file("extdata", "ex", package = "abseqR")

# Create the required input directories
dir.create("SRR_CTRL", showWarnings = FALSE, recursive = TRUE)
dir.create("SRR_EXP", showWarnings = FALSE, recursive = TRUE)

# Copy the example abseqPy output into the target directories
# This provides the necessary structure (e.g., 'auxiliary' directory) for abseqReport()
files_to_copy <- list.files(exdata, full.names = TRUE)
file.copy(files_to_copy, "SRR_CTRL", recursive = TRUE)
file.copy(files_to_copy, "SRR_EXP", recursive = TRUE)