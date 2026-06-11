library(Rqc)
library(ShortRead)

# Create the directory named 'folder' as expected by the input spec
dir.create("folder", showWarnings = FALSE)

# Find example FASTQ files shipped with ShortRead (as used in the vignette)
fastqDir <- system.file(package="ShortRead", "extdata/E-MTAB-1147")
files <- list.files(fastqDir, pattern = "fastq.gz", full.names = TRUE)

# Copy the example FASTQ files into 'folder'
file.copy(files, "folder")

# Write the pattern string to a file named 'pattern'
writeLines(".fastq.gz", "pattern")