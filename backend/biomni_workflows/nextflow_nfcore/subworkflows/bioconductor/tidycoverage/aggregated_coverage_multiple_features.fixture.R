library(tidyCoverage)
library(rtracklayer)
library(GenomicRanges)

# Load vignette data objects
data(ce, package = "tidyCoverage")
data(ac, package = "tidyCoverage")

# Define required files
required_files <- c(
    "TSSs.bed", 
    "conv_transcription_loci.bed", 
    "Scc1.bw", 
    "RNA.fwd.bw", 
    "RNA.rev.bw", 
    "PolII.bw", 
    "MNase.bw"
)

# Attempt to copy existing files from the package's extdata directory
extdata_dir <- system.file("extdata", package = "tidyCoverage")
for (f in required_files) {
    src <- file.path(extdata_dir, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    }
}

# Generate any missing BED files with required strand information
bed_files <- c("TSSs.bed", "conv_transcription_loci.bed")
for (f in bed_files) {
    if (!file.exists(f)) {
        gr <- GRanges(
            seqnames = "chr1", 
            ranges = IRanges(start = c(100, 500), width = 50), 
            strand = c("+", "+"), 
            name = c("feature1", "feature2"), 
            score = c(0, 0)
        )
        export(gr, f, format = "BED")
    }
}

# Generate any missing BigWig files
bw_files <- c("Scc1.bw", "RNA.fwd.bw", "RNA.rev.bw", "PolII.bw", "MNase.bw")
for (f in bw_files) {
    if (!file.exists(f)) {
        gr <- GRanges(
            seqnames = "chr1", 
            ranges = IRanges(start = seq(1, 1000, by = 10), width = 10), 
            score = runif(100)
        )
        seqlengths(gr) <- c(chr1 = 10000)
        export(gr, f, format = "BigWig")
    }
}