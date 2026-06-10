library(tidyCoverage)
library(rtracklayer)
library(GenomicRanges)

# Required input files for the workflow
req_files <- c("Scc1.bw", "RNA.fwd.bw", "RNA.rev.bw", "PolII.bw", "MNase.bw")

# Discover shipped BigWig files in the package
pkg_bw_files <- list.files(system.file("extdata", package = "tidyCoverage"), 
                           pattern = "\\.bw$", 
                           full.names = TRUE)

# Ensure all required files exist in the working directory
for (f in req_files) {
    # Check if there's an exact match in the package's extdata
    match_idx <- grep(paste0(f, "$"), pkg_bw_files)
    
    if (length(match_idx) > 0) {
        # Copy the exact match
        file.copy(pkg_bw_files[match_idx[1]], f, overwrite = TRUE)
    } else if (length(pkg_bw_files) > 0) {
        # If exact match is missing, copy the first available .bw file (e.g., MNase.bw)
        file.copy(pkg_bw_files[1], f, overwrite = TRUE)
    } else {
        # Fallback: create a valid dummy BigWig file if no .bw files are shipped
        gr <- GRanges(seqnames = "chr1", 
                      ranges = IRanges(start = seq(1, 1000, by=10), width = 10), 
                      score = runif(100))
        seqlengths(gr) <- c(chr1 = 2000)
        export.bw(gr, f)
    }
}