library(CRISPRseek)
library(Biostrings)

orig_file <- system.file('extdata', 'inputseq.fa', package = 'CRISPRseek')

if (file.exists(orig_file)) {
    file.copy(orig_file, "inputFilePath", overwrite = TRUE)
} else {
    # Fallback synthetic sequence if the package file is missing
    seqs <- DNAStringSet(c(
        Hsap_GATA1_ex2 = "CCAGTTTGTGGATCCTGCTCTGGGTGTCCTCCACACCAGAATCAGGGTGTGGAGGACACCAGAGCAGGCCAGAGCAGGATCCACAAACTGG"
    ))
    writeXStringSet(seqs, filepath = "inputFilePath")
}