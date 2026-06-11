library(rhinotypeR)
library(Biostrings)

# Try to find a shipped FASTA file in the package
pkg_fasta <- list.files(system.file("extdata", package="rhinotypeR"), 
                        pattern="user_sequences\\.fasta$", 
                        recursive=TRUE, full.names=TRUE)

aln_fasta <- list.files(system.file("extdata", package="rhinotypeR"), 
                        pattern="input_aln\\.fasta$", 
                        recursive=TRUE, full.names=TRUE)

if (length(pkg_fasta) > 0 && file.exists(pkg_fasta[1])) {
    file.copy(pkg_fasta[1], "user_sequences.fasta", overwrite = TRUE)
} else if (length(aln_fasta) > 0 && file.exists(aln_fasta[1])) {
    file.copy(aln_fasta[1], "user_sequences.fasta", overwrite = TRUE)
} else {
    # Fallback to the rhinovirusVP4 dataset from the vignette
    data(rhinovirusVP4, package = "rhinotypeR")
    
    if (inherits(rhinovirusVP4, "XStringSet")) {
        seqs <- rhinovirusVP4
    } else {
        seqs <- DNAStringSet(as.character(rhinovirusVP4))
        if (!is.null(names(rhinovirusVP4))) {
            names(seqs) <- names(rhinovirusVP4)
        } else {
            names(seqs) <- paste0("seq", seq_along(seqs))
        }
    }
    
    writeXStringSet(seqs, filepath = "user_sequences.fasta")
}