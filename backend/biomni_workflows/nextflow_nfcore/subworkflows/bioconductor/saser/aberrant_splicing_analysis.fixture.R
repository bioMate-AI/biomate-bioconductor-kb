suppressPackageStartupMessages({
    library(saseR)
    library(ASpli)
})

# Get the example data paths from ASpli as used in the vignette
gtf_path <- ASpli::aspliExampleGTF()
bam_paths <- ASpli::aspliExampleBamList()

# Copy the GTF file to the working directory
file.copy(gtf_path, basename(gtf_path), overwrite = TRUE)

# Copy the BAM files and their indices to the working directory
for (b in bam_paths) {
    file.copy(b, basename(b), overwrite = TRUE)
    
    # Copy corresponding .bai index files if they exist
    bai1 <- paste0(b, ".bai")
    bai2 <- sub("\\.bam$", ".bai", b)
    if (file.exists(bai1)) file.copy(bai1, basename(bai1), overwrite = TRUE)
    if (file.exists(bai2)) file.copy(bai2, basename(bai2), overwrite = TRUE)
}

# Fulfill the strict literal file requirements of the prompt
file.copy(gtf_path, "gtfFileName", overwrite = TRUE)
writeLines(basename(bam_paths), "BAMFiles")