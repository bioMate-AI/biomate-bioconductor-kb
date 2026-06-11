library(GenomicAlignments)
library(GenomicFeatures)
library(Rsamtools)
library(pasillaBamSubset)

# 1. Prepare BAM file from pasillaBamSubset
bam_path <- untreated3_chr4()
dest_bam <- "untreated3_chr4.bam"
file.copy(bam_path, dest_bam)

# Ensure BAM index exists
bai_path <- paste0(bam_path, ".bai")
if (file.exists(bai_path)) {
    file.copy(bai_path, paste0(dest_bam, ".bai"))
} else {
    indexBam(dest_bam)
}

# Serialize bamfiles input
bamfiles <- dest_bam
saveRDS(bamfiles, "bamfiles.rds")
saveRDS(bamfiles, "bamfiles")

# 2. Prepare features (GRangesList for summarizeOverlaps)
# Using coordinates that overlap with the reads in untreated3_chr4.bam (chr4)
features <- GRangesList(
    geneA = GRanges(seqnames = "chr4", ranges = IRanges(start = 169, end = 500), strand = "+"),
    geneB = GRanges(seqnames = "chr4", ranges = IRanges(start = 900, end = 1200), strand = "+")
)

# Serialize features input
saveRDS(features, "features.rds")
saveRDS(features, "features")