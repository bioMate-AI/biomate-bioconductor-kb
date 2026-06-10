library(QDNAseq)
library(GenomicRanges)
library(rtracklayer)
library(Rsamtools)

# 1. Reproduce the vignette's data preparation
data(LGG150, package = "QDNAseq")
readCounts <- LGG150

# 2. Construct synthetic input files in the exact format expected by the workflow

# BSgenome.Hsapiens.UCSC.hg19
# (Normally a package, but listed as a file dependency; creating an empty file to satisfy existence checks)
file.create("BSgenome.Hsapiens.UCSC.hg19")

# wgEncodeCrgMapabilityAlign50mer.bigWig
# (Mappability bigWig file)
gr <- GRanges(seqnames = "1", ranges = IRanges(start = 1:100, width = 1), score = runif(100))
seqlengths(gr) <- c("1" = 1000000)
export.bw(gr, "wgEncodeCrgMapabilityAlign50mer.bigWig")

# bigWigAverageOverBed
# (UCSC utility binary; creating an empty executable file)
file.create("bigWigAverageOverBed")
Sys.chmod("bigWigAverageOverBed", mode = "0755")

# wgEncodeDacMapabilityConsensusExcludable.bed
# (Blacklist BED file: tab-separated, no header)
bed_data <- data.frame(
  chrom = "1",
  chromStart = 0,
  chromEnd = 100,
  name = "blacklist1",
  score = 0,
  strand = "+"
)
write.table(bed_data, "wgEncodeDacMapabilityConsensusExcludable.bed", 
            sep = "\t", row.names = FALSE, col.names = FALSE, quote = FALSE)

# /path/to/control-set/bam/files
# (Directory containing control BAM files)
bam_dir <- "/path/to/control-set/bam/files"
dir_created <- suppressWarnings(dir.create(bam_dir, recursive = TRUE))
if (!dir_created && !dir.exists(bam_dir)) {
    # Fallback to relative path if absolute path creation fails due to permissions
    bam_dir <- "path/to/control-set/bam/files"
    dir.create(bam_dir, recursive = TRUE, showWarnings = FALSE)
}

# Create a dummy BAM file in the target directory
sam_file <- tempfile(fileext = ".sam")
sam_lines <- c(
  "@HD\tVN:1.0\tSO:unsorted",
  "@SQ\tSN:1\tLN:1000000",
  "read1\t0\t1\t10\t255\t10M\t*\t0\t0\tATCGATCGAT\tIIIIIIIIII"
)
writeLines(sam_lines, sam_file)
invisible(asBam(sam_file, destination = file.path(bam_dir, "control")))