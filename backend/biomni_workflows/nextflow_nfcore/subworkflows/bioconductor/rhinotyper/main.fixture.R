library(rhinotypeR)
library(Biostrings)

data(rhinovirusVP4, package = "rhinotypeR")
writeXStringSet(rhinovirusVP4, filepath = "user_sequences.fasta")

shipped_aln <- system.file("extdata", "input_aln.fasta", package = "rhinotypeR")
if (file.exists(shipped_aln) && nzchar(shipped_aln)) {
    file.copy(shipped_aln, "input_aln.fasta", overwrite = TRUE)
} else {
    aln <- alignToRefs(
        seqData   = rhinovirusVP4,
        method    = "ClustalW",
        trimToRef = TRUE,
        refName   = "JN855971.1_A107"
    )
    writeXStringSet(as(aln, "DNAStringSet"), filepath = "input_aln.fasta")
}