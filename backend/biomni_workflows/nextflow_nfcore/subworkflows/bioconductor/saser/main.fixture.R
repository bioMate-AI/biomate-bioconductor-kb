library(saseR)
suppressWarnings(library(ASpli))

# Get example data paths from ASpli
gtfFileName_orig <- ASpli::aspliExampleGTF()
BAMFiles_orig <- ASpli::aspliExampleBamList()

# Copy the GTF file to the exact expected input name
file.copy(gtfFileName_orig, "gtfFileName", overwrite = TRUE)

# Copy the first BAM file to the exact expected input name "BAMFiles"
file.copy(BAMFiles_orig[1], "BAMFiles", overwrite = TRUE)

# Also copy all original BAM files and their indices to the working directory 
# in case the workflow references them by their original basenames
file.copy(gtfFileName_orig, basename(gtfFileName_orig), overwrite = TRUE)
for (b in BAMFiles_orig) {
    file.copy(b, basename(b), overwrite = TRUE)
    
    # Copy .bam.bai if it exists
    bai1 <- paste0(b, ".bai")
    if (file.exists(bai1)) {
        file.copy(bai1, basename(bai1), overwrite = TRUE)
    }
    
    # Copy .bai (replacing .bam) if it exists
    bai2 <- sub("\\.bam$", ".bai", b)
    if (file.exists(bai2)) {
        file.copy(bai2, basename(bai2), overwrite = TRUE)
    }
}