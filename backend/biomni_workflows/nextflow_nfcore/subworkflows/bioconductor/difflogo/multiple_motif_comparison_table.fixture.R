library(DiffLogo)

# Prepare motifs_dna.txt
dna_src <- system.file("extdata/alignments/Mad.txt", package = "DiffLogo")
if (file.exists(dna_src)) {
    file.copy(dna_src, "motifs_dna.txt", overwrite = TRUE)
} else {
    # Fallback if the file is missing
    writeLines(c("ACGT", "ACGT", "ACGT"), "motifs_dna.txt")
}

# Prepare motifs_asn.fa
asn_src <- system.file("extdata/alignments/F-box_fungi.seq.fa", package = "DiffLogo")
if (file.exists(asn_src)) {
    file.copy(asn_src, "motifs_asn.fa", overwrite = TRUE)
} else {
    # Fallback if the file is missing
    writeLines(c(">seq1", "ACDEFGHIKLMNPQRSTVWY", ">seq2", "ACDEFGHIKLMNPQRSTVWY"), "motifs_asn.fa")
}