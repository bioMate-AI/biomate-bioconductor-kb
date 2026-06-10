library(rhinotypeR)
library(Biostrings)
library(msa)

# Helper to find and copy shipped files
copy_shipped_file <- function(pattern, dest) {
    files <- list.files(system.file("extdata", package = "rhinotypeR"), 
                        pattern = pattern, recursive = TRUE, full.names = TRUE)
    if (length(files) > 0 && file.exists(files[1])) {
        file.copy(files[1], dest, overwrite = TRUE)
        return(TRUE)
    }
    return(FALSE)
}

# 1. test_translated.fasta (aligned amino acid sequences)
if (!copy_shipped_file("test_translated\\.fasta$", "test_translated.fasta")) {
    # Fallback: reproduce from vignette data
    data(rhinovirusVP4, package = "rhinotypeR")
    aln_no_gaps <- Biostrings::DNAStringSet(gsub("-", "", as.character(rhinovirusVP4)))
    aa <- Biostrings::translate(aln_no_gaps)
    aa_aln <- msa::msa(aa)
    writeXStringSet(as(aa_aln, "AAStringSet"), "test_translated.fasta")
}

# 2. user_sequences.fasta (unaligned DNA sequences)
if (!copy_shipped_file("user_sequences\\.fasta$", "user_sequences.fasta")) {
    # Fallback: reproduce from vignette data
    data(rhinovirusVP4, package = "rhinotypeR")
    unaligned <- Biostrings::DNAStringSet(gsub("-", "", as.character(rhinovirusVP4)))
    writeXStringSet(unaligned, "user_sequences.fasta")
}