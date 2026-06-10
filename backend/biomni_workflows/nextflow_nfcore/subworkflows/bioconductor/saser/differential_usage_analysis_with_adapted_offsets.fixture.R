suppressPackageStartupMessages({
    library(saseR)
    library(ASpli)
})

# Get paths to the example data shipped with ASpli (as used in the vignette)
gtf_src <- ASpli::aspliExampleGTF()
bam_srcs <- ASpli::aspliExampleBamList()

# Copy the original files to the working directory
file.copy(gtf_src, basename(gtf_src), overwrite = TRUE)
for (b in bam_srcs) {
    file.copy(b, basename(b), overwrite = TRUE)
    
    # Copy index files if they exist
    bai1 <- sub("\\.bam$", ".bai", b)
    bai2 <- paste0(b, ".bai")
    if (file.exists(bai1)) {
        file.copy(bai1, basename(bai1), overwrite = TRUE)
    } else if (file.exists(bai2)) {
        file.copy(bai2, basename(bai2), overwrite = TRUE)
    }
}

# Guarantee the literal declared input files exist in the working directory
file.copy(gtf_src, "gtfFileName", overwrite = TRUE)
file.copy(bam_srcs[1], "BAMFiles", overwrite = TRUE)