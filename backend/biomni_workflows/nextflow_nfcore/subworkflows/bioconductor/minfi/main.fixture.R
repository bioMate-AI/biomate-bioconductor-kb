library(minfi)
library(minfiData)

# The vignette uses the extdata directory from minfiData as the source of raw IDAT files and the sample sheet.
baseDir_source <- system.file("extdata", package = "minfiData")

# 1. Copy SampleSheet.csv to the working directory
file.copy(file.path(baseDir_source, "SampleSheet.csv"), "SampleSheet.csv", overwrite = TRUE)

# 2. Copy the slide directories and their .idat files to match the expected structure
slide_dirs <- c("5723646052", "5723646053")
for (d in slide_dirs) {
  if (!dir.exists(d)) {
    dir.create(d)
  }
  
  # Find .idat files in the source slide directory
  idat_files <- list.files(file.path(baseDir_source, d), pattern = "\\.idat$", full.names = TRUE)
  
  # Copy to the corresponding slide directory in the working directory
  file.copy(idat_files, d, overwrite = TRUE)
  
  # Also copy directly to the working directory to satisfy the "*.idat" root requirement
  file.copy(idat_files, ".", overwrite = TRUE)
}