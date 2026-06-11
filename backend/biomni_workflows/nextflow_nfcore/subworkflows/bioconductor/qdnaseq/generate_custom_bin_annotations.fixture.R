suppressPackageStartupMessages({
    library(QDNAseq)
    library(rtracklayer)
    library(GenomicRanges)
})

# 1. Reproduce the VIGNETTE'S OWN data-preparation code
data(LGG150, package="QDNAseq")
readCounts <- LGG150

# 2. Serialize to EACH declared input file
# Create dummy package/file reference
writeLines("dummy", "BSgenome.Hsapiens.UCSC.hg19")

# Create valid GRanges to export as bigWig and BED
gr <- GRanges(seqnames="chr1", ranges=IRanges(start=1, end=100), score=1)
seqlengths(gr) <- c(chr1=1000)

# Create directories relative to working directory
dir.create("path/to/control-set/bam/files", recursive=TRUE, showWarnings=FALSE)

# Export valid bigWig and BED files
export.bw(gr, "path/to/wgEncodeCrgMapabilityAlign50mer.bigWig")
export.bed(gr, "path/to/wgEncodeDacMapabilityConsensusExcludable.bed")
writeLines("dummy executable", "path/to/bigWigAverageOverBed")

# Provide a BAM file (use package extdata if available, else dummy)
bam_files <- list.files(system.file("extdata", package="QDNAseq"), pattern="\\.bam$", full.names=TRUE)
if (length(bam_files) > 0) {
    file.copy(bam_files[1], "path/to/control-set/bam/files/dummy.bam", overwrite=TRUE)
} else {
    writeLines("dummy bam content", "path/to/control-set/bam/files/dummy.bam")
}

# Also try to create absolute paths if permissions allow
tryCatch({
    dir.create("/path/to/control-set/bam/files", recursive=TRUE, showWarnings=FALSE)
    export.bw(gr, "/path/to/wgEncodeCrgMapabilityAlign50mer.bigWig")
    export.bed(gr, "/path/to/wgEncodeDacMapabilityConsensusExcludable.bed")
    writeLines("dummy executable", "/path/to/bigWigAverageOverBed")
    if (length(bam_files) > 0) {
        file.copy(bam_files[1], "/path/to/control-set/bam/files/dummy.bam", overwrite=TRUE)
    } else {
        writeLines("dummy bam content", "/path/to/control-set/bam/files/dummy.bam")
    }
}, error = function(e) NULL, warning = function(w) NULL)

# Also create flat files in working directory just in case the parser stripped paths
export.bw(gr, "wgEncodeCrgMapabilityAlign50mer.bigWig")
export.bed(gr, "wgEncodeDacMapabilityConsensusExcludable.bed")
writeLines("dummy executable", "bigWigAverageOverBed")