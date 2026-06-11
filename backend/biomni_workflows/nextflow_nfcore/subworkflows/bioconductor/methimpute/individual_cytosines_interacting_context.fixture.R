library(methimpute)

bsseeker_src <- system.file("extdata", "arabidopsis_bsseeker.txt.gz", package="methimpute")
fasta_src <- system.file("extdata", "arabidopsis_sequence.fa.gz", package="methimpute")

if (file.exists(bsseeker_src)) {
    file.copy(bsseeker_src, "bsseeker_file.txt.gz", overwrite = TRUE)
} else {
    stop("Source bsseeker file not found in methimpute package.")
}

if (file.exists(fasta_src)) {
    file.copy(fasta_src, "genome_sequence.fa.gz", overwrite = TRUE)
} else {
    stop("Source fasta file not found in methimpute package.")
}