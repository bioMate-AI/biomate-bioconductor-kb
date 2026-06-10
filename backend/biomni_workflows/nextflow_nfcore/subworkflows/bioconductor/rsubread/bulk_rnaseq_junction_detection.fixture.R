library(Rsubread)

extdata_dir <- system.file("extdata", package="Rsubread")

# Find and copy the reference genome FASTA
ref_candidates <- list.files(extdata_dir, pattern="\\.fa$", full.names=TRUE)
if(length(ref_candidates) > 0) {
    file.copy(ref_candidates[1], "genome.fa", overwrite=TRUE)
} else {
    # Fallback synthetic FASTA if not found
    writeLines(c(">chr_dummy", paste(rep("ACGT", 25), collapse="")), "genome.fa")
}

# Find and copy the RNA-seq reads
reads_candidates <- list.files(extdata_dir, pattern="reads\\.txt\\.gz$", full.names=TRUE)
if(length(reads_candidates) > 0) {
    file.copy(reads_candidates[1], "rnaseq-reads.txt.gz", overwrite=TRUE)
} else {
    reads_candidates_alt <- list.files(extdata_dir, pattern="\\.txt\\.gz$", full.names=TRUE)
    if(length(reads_candidates_alt) > 0) {
        file.copy(reads_candidates_alt[1], "rnaseq-reads.txt.gz", overwrite=TRUE)
    } else {
        # Fallback synthetic FASTQ-like reads if not found
        gz <- gzfile("rnaseq-reads.txt.gz", "w")
        writeLines(c("@read1", "ACGT", "+", "IIII"), gz)
        close(gz)
    }
}