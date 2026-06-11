library(yamss)
library(mtbls2)
library(S4Vectors)

# Locate the raw mass spectrometry files from the companion data package
filepath <- file.path(find.package("mtbls2"), "mzML")
original_files <- list.files(filepath, pattern = "MSpos-Ex1", recursive = TRUE, full.names = TRUE)

# Copy files to the working directory to ensure they are accessible
files <- basename(original_files)
file.copy(original_files, files)

# Save the vector of file paths
saveRDS(files, "files.rds")

# Create the colData DataFrame as described in the vignette
classes <- rep(c("wild-type", "mutant"), each = 4)
colData <- DataFrame(sampClasses = classes, ionmode = "pos")

# Save the colData object
saveRDS(colData, "colData.rds")