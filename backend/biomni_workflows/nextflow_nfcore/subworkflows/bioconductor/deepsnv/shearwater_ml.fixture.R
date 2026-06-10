library(deepSNV)

# Locate the BAM files shipped with the deepSNV package
bam_files <- c(
    system.file("extdata", "test.bam", package="deepSNV"), 
    system.file("extdata", "control.bam", package="deepSNV")
)

# Copy the BAM files and their indices to the working directory
for (f in bam_files) {
    if (file.exists(f)) {
        file.copy(f, basename(f), overwrite = TRUE)
    }
    
    # Also copy the corresponding .bai index files if they exist
    bai_file <- paste0(f, ".bai")
    if (file.exists(bai_file)) {
        file.copy(bai_file, basename(bai_file), overwrite = TRUE)
    }
}