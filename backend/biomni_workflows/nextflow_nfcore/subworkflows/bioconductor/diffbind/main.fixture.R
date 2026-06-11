library(DiffBind)

extra_dir <- system.file("extra", package="DiffBind")

# Copy the sample sheet
file.copy(file.path(extra_dir, "tamoxifen.csv"), "tamoxifen.csv", overwrite = TRUE)

# Read the sample sheet to get the relative paths for BAM and BED files
samples <- read.csv("tamoxifen.csv")

# Helper function to copy files and create necessary directories
copy_file <- function(rel_path) {
    if (!is.na(rel_path) && rel_path != "") {
        src <- file.path(extra_dir, rel_path)
        if (file.exists(src)) {
            dir.create(dirname(rel_path), showWarnings = FALSE, recursive = TRUE)
            file.copy(src, rel_path, overwrite = TRUE)
        }
    }
}

# Copy BAM files and their indices for ChIP reads
for (bam in samples$bamReads) {
    copy_file(bam)
    copy_file(paste0(bam, ".bai"))
    copy_file(sub("\\.bam$", ".bai", bam))
}

# Copy BAM files and their indices for Control reads
if ("bamControl" %in% colnames(samples)) {
    for (bam in samples$bamControl) {
        copy_file(bam)
        copy_file(paste0(bam, ".bai"))
        copy_file(sub("\\.bam$", ".bai", bam))
    }
}

# Copy Peak files
for (peak in samples$Peaks) {
    copy_file(peak)
}