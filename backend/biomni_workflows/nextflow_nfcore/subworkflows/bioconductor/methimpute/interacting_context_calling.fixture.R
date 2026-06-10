library(methimpute)

# 1. arabidopsis_bsseeker.txt.gz
bsseeker_src <- system.file("extdata", "arabidopsis_bsseeker.txt.gz", package="methimpute")
if (bsseeker_src == "" || !file.exists(bsseeker_src)) {
    bsseeker_src <- list.files(system.file(package="methimpute"), pattern="arabidopsis_bsseeker.txt.gz", recursive=TRUE, full.names=TRUE)[1]
}

if (!is.na(bsseeker_src) && file.exists(bsseeker_src)) {
    file.copy(bsseeker_src, "arabidopsis_bsseeker.txt.gz", overwrite=TRUE)
} else {
    # Fallback dummy BSSeeker file
    df <- data.frame(
        chr = "chr1",
        pos = c(34, 80, 84, 85, 86, 533552, 533554, 533595, 533601, 533614),
        strand = c("-", "-", "+", "+", "+", "-", "-", "+", "+", "+"),
        context = c("CHG", "CHH", "CHH", "CHH", "CHH", "CG", "CG", "CHG", "CHG", "CG"),
        dinucleotide = c("CA", "CC", "CT", "CT", "CT", "CG", "CG", "CA", "CA", "CG"),
        meth_level = c(0, 2/11, 1, 1, 1, 1, 1, 0, 0, 0),
        meth_counts = c(0, 2, 1, 1, 1, 2, 2, 0, 0, 0),
        total_counts = c(4, 11, 1, 1, 1, 2, 2, 1, 2, 2)
    )
    gz1 <- gzfile("arabidopsis_bsseeker.txt.gz", "w")
    write.table(df, gz1, sep="\t", quote=FALSE, row.names=FALSE, col.names=FALSE)
    close(gz1)
}

# 2. arabidopsis_sequence.fa.gz
fasta_src <- system.file("extdata", "arabidopsis_sequence.fa.gz", package="methimpute")
if (fasta_src == "" || !file.exists(fasta_src)) {
    fasta_src <- list.files(system.file(package="methimpute"), pattern="arabidopsis_sequence.fa.gz", recursive=TRUE, full.names=TRUE)[1]
}

if (!is.na(fasta_src) && file.exists(fasta_src)) {
    file.copy(fasta_src, "arabidopsis_sequence.fa.gz", overwrite=TRUE)
} else {
    # Fallback dummy FASTA file
    seq_len <- 533620
    seq_vec <- rep("N", seq_len)
    seq_vec[34] <- "C"
    seq_vec[80] <- "C"
    seq_vec[84] <- "C"
    seq_vec[85] <- "C"
    seq_vec[86] <- "C"
    seq_vec[533552] <- "C"
    seq_vec[533554] <- "C"
    seq_vec[533595] <- "C"
    seq_vec[533601] <- "C"
    seq_vec[533614] <- "C"
    
    seq_str <- paste(seq_vec, collapse="")
    
    gz2 <- gzfile("arabidopsis_sequence.fa.gz", "w")
    writeLines(c(">chr1", seq_str), gz2)
    close(gz2)
}