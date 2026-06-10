library(RiboDiPA)
library(Rsamtools)
library(rtracklayer)
library(GenomicRanges)

# Define the expected file names
bam_files <- c("WT1.bam", "WT2.bam", "MUT1.bam", "MUT2.bam")
gtf_file <- "eg.gtf"

# 1. Create a dummy GTF file
# The vignette uses an interval on chrIV containing gene YDR050C
gr_gtf <- GRanges(
    seqnames = "chrIV",
    ranges = IRanges(start = c(553166, 553200), end = c(553190, 553250)),
    strand = "+",
    type = "exon",
    gene_id = "YDR050C",
    transcript_id = "YDR050C_mRNA"
)
export(gr_gtf, gtf_file, format = "gtf")

# 2. Create dummy BAM files
# We generate synthetic SAM files and convert them to BAM format
create_dummy_bam <- function(file_name) {
    sam_lines <- c(
        "@HD\tVN:1.4\tSO:coordinate",
        "@SQ\tSN:chrIV\tLN:1000000"
    )
    
    # Generate 50 dummy reads of length 28 (as expected by the vignette's P-site mapping)
    for (i in 1:50) {
        flag <- 0
        rname <- "chrIV"
        pos <- 553170 + i
        mapq <- 255
        cigar <- "28M"
        rnext <- "*"
        pnext <- 0
        tlen <- 0
        seq_str <- paste(rep("A", 28), collapse="")
        qual <- paste(rep("I", 28), collapse="")
        
        sam_lines <- c(sam_lines, paste(paste0("read", i), flag, rname, pos, mapq, cigar, rnext, pnext, tlen, seq_str, qual, sep="\t"))
    }
    
    sam_file <- sub("\\.bam$", ".sam", file_name)
    writeLines(sam_lines, sam_file)
    
    # Convert SAM to BAM and index it
    asBam(sam_file, destination = sub("\\.bam$", "", file_name), overwrite = TRUE, indexDestination = TRUE)
    unlink(sam_file)
}

for (bf in bam_files) {
    create_dummy_bam(bf)
}

# Define bam_path as used in the vignette
bam_path <- c(bam_files, gtf_file)

# Verify that all files exist
stopifnot(all(file.exists(bam_path)))