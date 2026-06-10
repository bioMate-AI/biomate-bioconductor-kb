library(R4RNA)
library(Biostrings)

fasta_file <- system.file("extdata", "fasta.txt", package = "R4RNA")
if (file.exists(fasta_file)) {
    file.copy(fasta_file, "alignment.fasta", overwrite = TRUE)
} else {
    seqs <- BStringSet(c(seq1 = "GGCGCGUUAACAAAGCGGUU", seq2 = "GGCGCGUUAACAAAGCGGUU"))
    writeXStringSet(seqs, "alignment.fasta")
}

known_file <- system.file("extdata", "vienna.txt", package = "R4RNA")
if (file.exists(known_file)) {
    file.copy(known_file, "known_structure.dbn", overwrite = TRUE)
} else {
    writeLines(c(">seq1", "GGCGCGUUAACAAAGCGGUU", "(((((((......)))))))"), "known_structure.dbn")
}