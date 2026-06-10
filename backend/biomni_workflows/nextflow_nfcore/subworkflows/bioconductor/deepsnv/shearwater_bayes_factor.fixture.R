library(deepSNV)

# Locate the BAM files shipped with the deepSNV package
test_bam <- system.file("extdata", "test.bam", package="deepSNV")
control_bam <- system.file("extdata", "control.bam", package="deepSNV")

# Copy the BAM files and their indices to the working directory
file.copy(test_bam, "test.bam", overwrite = TRUE)
file.copy(paste0(test_bam, ".bai"), "test.bam.bai", overwrite = TRUE)
file.copy(control_bam, "control.bam", overwrite = TRUE)
file.copy(paste0(control_bam, ".bai"), "control.bam.bai", overwrite = TRUE)

# Create the vector of paths to the BAM files as expected by the workflow
files <- c("test.bam", "control.bam")

# Serialize the vector to the declared input file 'files'
saveRDS(files, "files")