library(MethTargetedNGS)

msa_candidates <- list.files(system.file("extdata", package="MethTargetedNGS"), pattern="msa\\.fasta$", recursive=TRUE, full.names=TRUE)
if (length(msa_candidates) > 0) {
    file.copy(msa_candidates[1], "msa.fasta", overwrite=TRUE)
} else {
    writeLines(c(">seq1", "ACGT", ">seq2", "ACGT"), "msa.fasta")
}

tumor_candidates <- list.files(system.file("extdata", package="MethTargetedNGS"), pattern="Tumor\\.fasta$", recursive=TRUE, full.names=TRUE)
if (length(tumor_candidates) > 0) {
    file.copy(tumor_candidates[1], "Tumor.fasta", overwrite=TRUE)
} else {
    writeLines(c(">tumor1", "ACGT", ">tumor2", "ACGT"), "Tumor.fasta")
}