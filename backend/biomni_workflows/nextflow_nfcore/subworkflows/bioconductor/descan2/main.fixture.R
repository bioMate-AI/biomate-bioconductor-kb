library(DEScan2)
library(GenomicRanges)

# 1. Locate and copy BAM files to the working directory
bam_dir <- system.file("extdata", "bam", package = "DEScan2")
bam_files <- list.files(bam_dir, pattern = "bam$", full.names = TRUE)
if (length(bam_files) > 0) {
    file.copy(bam_files, ".")
}

# The prompt specifies 'bam.files' as an input file (character vector of paths).
# We serialize the local paths to an RDS file to satisfy this requirement.
saveRDS(basename(bam_files), "bam.files")

# 2. Locate and copy the pre-computed GRangesList (peaksGRL_all_files.rds)
peaks_file <- system.file("extdata", "peaks", "RData", "peaksGRL_all_files.rds", package = "DEScan2")

if (file.exists(peaks_file)) {
    file.copy(peaks_file, "peaksGRL_all_files.rds")
} else {
    # Fallback: search for the file if it was moved in newer package versions
    peaks_files_alt <- list.files(system.file("extdata", package = "DEScan2"), 
                                  pattern = "peaksGRL_all_files\\.rds$", 
                                  recursive = TRUE, full.names = TRUE)
    if (length(peaks_files_alt) > 0) {
        file.copy(peaks_files_alt[1], "peaksGRL_all_files.rds")
    } else {
        # Fallback: construct a minimal synthetic GRangesList matching the vignette structure
        gr <- GRanges(
            seqnames = "chr19",
            ranges = IRanges(start = c(57220100, 57224200), end = c(57220599, 57224799)),
            `z-score` = c(16.3522, 19.7854)
        )
        peaksGRL <- GRangesList(sample1 = gr)
        saveRDS(peaksGRL, "peaksGRL_all_files.rds")
    }
}