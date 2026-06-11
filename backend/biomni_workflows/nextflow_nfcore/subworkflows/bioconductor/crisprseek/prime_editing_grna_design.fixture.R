library(CRISPRseek)
library(Biostrings)

inputFilePath <- system.file('extdata', 'inputseq.fa', package = 'CRISPRseek')

if (inputFilePath != "" && file.exists(inputFilePath)) {
    file.copy(inputFilePath, "inputseq.fa", overwrite = TRUE)
} else {
    # Fallback: Create a synthetic inputseq.fa containing the target sequences 
    # referenced in the vignette's output (Hsap_GATA1_ex2)
    synthetic_seq <- DNAStringSet(c(
        Hsap_GATA1_ex2 = "CCAGTTTGTGGATCCTGCTCTGGGTGTCCTCCACACCAGAATCAGGGGTGTGGAGGACACCAGAGCAGGCCAGAGCAGGATCCACAAACTGG"
    ))
    writeXStringSet(synthetic_seq, "inputseq.fa")
}