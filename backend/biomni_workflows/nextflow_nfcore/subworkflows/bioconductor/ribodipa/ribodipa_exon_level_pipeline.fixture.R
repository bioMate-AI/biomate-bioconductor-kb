library(RiboDiPA)
library(Rsamtools)
library(rtracklayer)
library(GenomicRanges)

bam_names <- c("WT1.bam", "WT2.bam", "MUT1.bam", "MUT2.bam")
gtf_name <- "eg.gtf"

# Check if the package ships the required files in extdata
extdata_dir <- system.file("extdata", package="RiboDiPA")
ext_bams <- list.files(extdata_dir, pattern="\\.bam$", full.names=TRUE)
ext_gtfs <- list.files(extdata_dir, pattern="\\.gtf$", full.names=TRUE)

if (length(ext_bams) >= 4 && length(ext_gtfs) >= 1) {
    for (i in 1:4) {
        file.copy(ext_bams[i], bam_names[i], overwrite = TRUE)
        bai_file <- paste0(ext_bams[i], ".bai")
        if (file.exists(bai_file)) {
            file.copy(bai_file, paste0(bam_names[i], ".bai"), overwrite = TRUE)
        }
    }
    file.copy(ext_gtfs[1], gtf_name, overwrite = TRUE)
} else {
    # Generate a synthetic GTF file
    gr <- GRanges(
        seqnames = "chrIV",
        ranges = IRanges(start = c(553200, 553600), width = c(100, 100)),
        strand = "+",
        type = "exon",
        gene_id = "YDR050C",
        transcript_id = "YDR050C_mRNA"
    )
    export(gr, gtf_name, format = "gtf")

    # Generate synthetic BAM files
    sam_header <- c("@HD\tVN:1.4\tSO:coordinate", "@SQ\tSN:chrIV\tLN:1531933")
    reads <- c(
        paste("r1", 0, "chrIV", 553210, 255, "28M", "*", 0, 0, paste(rep("A", 28), collapse=""), paste(rep("I", 28), collapse=""), sep="\t"),
        paste("r2", 0, "chrIV", 553220, 255, "29M", "*", 0, 0, paste(rep("C", 29), collapse=""), paste(rep("I", 29), collapse=""), sep="\t"),
        paste("r3", 0, "chrIV", 553230, 255, "30M", "*", 0, 0, paste(rep("G", 30), collapse=""), paste(rep("I", 30), collapse=""), sep="\t"),
        paste("r4", 0, "chrIV", 553240, 255, "31M", "*", 0, 0, paste(rep("T", 31), collapse=""), paste(rep("I", 31), collapse=""), sep="\t")
    )
    sam_content <- c(sam_header, reads)

    for (bf in bam_names) {
        sf <- sub("\\.bam$", ".sam", bf)
        writeLines(sam_content, sf)
        asBam(sf, destination = sub("\\.bam$", "", bf), overwrite = TRUE, indexDestination = TRUE)
        unlink(sf)
    }
}

# The workflow expects bam_path to be a vector containing the 4 BAMs and 1 GTF
bam_path <- c(bam_names, gtf_name)

# Verify files exist
stopifnot(all(file.exists(bam_path)))