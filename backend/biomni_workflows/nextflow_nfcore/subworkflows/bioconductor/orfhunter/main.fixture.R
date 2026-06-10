library(ORFhunteR)
library(Biostrings)

# Locate the ground truth files shipped with the package
lnc_file <- list.files(system.file("extdata", package="ORFhunteR"), pattern="lncRNA_candidates.fasta", full.names=TRUE, recursive=TRUE)[1]
mrna_file <- list.files(system.file("extdata", package="ORFhunteR"), pattern="mRNA_true.fasta", full.names=TRUE, recursive=TRUE)[1]

# Load or generate pseudo-ORFs from lncRNAs
if (!is.na(lnc_file) && file.exists(lnc_file)) {
    lnc_seqs <- readDNAStringSet(lnc_file)
} else {
    # Generate synthetic sequences (1000 sequences to satisfy potential subsetting like N <- 1000)
    lnc_seqs <- DNAStringSet(rep(c(
        "ATGGGCCTCTAA", 
        "ATGGCTGCGTAA",
        "ATGCCGGCATGA",
        "ATGAAATTTGGGCCCTAA",
        "ATGGGGAAAAAACCCGGGTAG"
    ), 200))
    names(lnc_seqs) <- paste0("lnc_seq", 1:1000)
}

# Load or generate true ORFs from mRNAs
if (!is.na(mrna_file) && file.exists(mrna_file)) {
    mrna_seqs <- readDNAStringSet(mrna_file)
} else {
    # Generate synthetic sequences
    mrna_seqs <- DNAStringSet(rep(c(
        "ATGGGCCTCTAA", 
        "ATGGCTGCGTAA",
        "ATGCCGGCATGA",
        "ATGAAATTTGGGCCCTAA",
        "ATGGGGAAAAAACCCGGGTAG"
    ), 200))
    names(mrna_seqs) <- paste0("mrna_seq", 1:1000)
}

# Write the required input files to the working directory
writeXStringSet(lnc_seqs, filepath="fileORFLncRNAs.fasta.gz", compress=TRUE)
writeXStringSet(mrna_seqs, filepath="fileORFmRNAs.fasta.gz", compress=TRUE)