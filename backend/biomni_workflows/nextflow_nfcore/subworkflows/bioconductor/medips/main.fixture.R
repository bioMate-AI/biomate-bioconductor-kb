library(MEDIPS)
library(MEDIPSData)

# Locate the original BAM files provided by the MEDIPSData package
bam.file.hESCs.Rep1.MeDIP.src <- system.file("extdata", "hESCs.MeDIP.Rep1.chr22.bam", package="MEDIPSData")
bam.file.hESCs.Rep2.MeDIP.src <- system.file("extdata", "hESCs.MeDIP.Rep2.chr22.bam", package="MEDIPSData")
bam.file.hESCs.Input.src <- system.file("extdata", "hESCs.Input.chr22.bam", package="MEDIPSData")
bam.file.DE.Input.src <- system.file("extdata", "DE.Input.chr22.bam", package="MEDIPSData")

# Copy the BAM files to the exact filenames expected by the workflow
file.copy(bam.file.hESCs.Rep1.MeDIP.src, "bam.file.hESCs.Rep1.MeDIP", overwrite = TRUE)
file.copy(bam.file.hESCs.Rep2.MeDIP.src, "bam.file.hESCs.Rep2.MeDIP", overwrite = TRUE)
file.copy(bam.file.hESCs.Input.src, "bam.file.hESCs.Input", overwrite = TRUE)
file.copy(bam.file.DE.Input.src, "bam.file.DE.Input", overwrite = TRUE)

# Copy the BAM index files if they exist
if (file.exists(paste0(bam.file.hESCs.Rep1.MeDIP.src, ".bai"))) {
    file.copy(paste0(bam.file.hESCs.Rep1.MeDIP.src, ".bai"), "bam.file.hESCs.Rep1.MeDIP.bai", overwrite = TRUE)
}
if (file.exists(paste0(bam.file.hESCs.Rep2.MeDIP.src, ".bai"))) {
    file.copy(paste0(bam.file.hESCs.Rep2.MeDIP.src, ".bai"), "bam.file.hESCs.Rep2.MeDIP.bai", overwrite = TRUE)
}
if (file.exists(paste0(bam.file.hESCs.Input.src, ".bai"))) {
    file.copy(paste0(bam.file.hESCs.Input.src, ".bai"), "bam.file.hESCs.Input.bai", overwrite = TRUE)
}
if (file.exists(paste0(bam.file.DE.Input.src, ".bai"))) {
    file.copy(paste0(bam.file.DE.Input.src, ".bai"), "bam.file.DE.Input.bai", overwrite = TRUE)
}

# Also copy to their original basenames to ensure compatibility with any basename() calls
file.copy(bam.file.hESCs.Rep1.MeDIP.src, basename(bam.file.hESCs.Rep1.MeDIP.src), overwrite = TRUE)
file.copy(bam.file.hESCs.Rep2.MeDIP.src, basename(bam.file.hESCs.Rep2.MeDIP.src), overwrite = TRUE)
file.copy(bam.file.hESCs.Input.src, basename(bam.file.hESCs.Input.src), overwrite = TRUE)
file.copy(bam.file.DE.Input.src, basename(bam.file.DE.Input.src), overwrite = TRUE)