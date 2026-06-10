library(methimpute)

extdata_dir <- system.file("extdata", package="methimpute")

# 1. arabidopsis_bsseeker.txt.gz
bsseeker_candidates <- list.files(extdata_dir, pattern="bsseeker", full.names=TRUE, ignore.case=TRUE)
if (length(bsseeker_candidates) > 0) {
    file.copy(bsseeker_candidates[1], "arabidopsis_bsseeker.txt.gz", overwrite=TRUE)
} else {
    # Fallback synthetic data
    gz1 <- gzfile("arabidopsis_bsseeker.txt.gz", "w")
    writeLines(c(
        "chr1\tC\t34\t-\tCHG\t0:4",
        "chr1\tC\t80\t-\tCHH\t2:9",
        "chr1\tC\t84\t+\tCHH\t1:1"
    ), gz1)
    close(gz1)
}

# 2. arabidopsis_sequence.fa.gz
fasta_candidates <- list.files(extdata_dir, pattern="sequence", full.names=TRUE, ignore.case=TRUE)
if (length(fasta_candidates) == 0) {
    fasta_candidates <- list.files(extdata_dir, pattern="\\.fa\\.gz$", full.names=TRUE, ignore.case=TRUE)
}
if (length(fasta_candidates) > 0) {
    file.copy(fasta_candidates[1], "arabidopsis_sequence.fa.gz", overwrite=TRUE)
} else {
    # Fallback synthetic data
    gz2 <- gzfile("arabidopsis_sequence.fa.gz", "w")
    writeLines(c(
        ">chr1",
        "NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNCNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNCNNNCNNNCNNN"
    ), gz2)
    close(gz2)
}