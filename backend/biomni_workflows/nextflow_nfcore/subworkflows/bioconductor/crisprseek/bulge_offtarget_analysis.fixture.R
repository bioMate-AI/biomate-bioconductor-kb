library(CRISPRseek)

inputFilePath <- system.file('extdata', 'inputseq.fa', package = 'CRISPRseek')
if (file.exists(inputFilePath)) {
    file.copy(inputFilePath, "inputseq.fa", overwrite = TRUE)
} else {
    # Fallback in case the file is missing or moved
    cat(">Hsap_GATA1_ex2\nCCAGTTTGTGGATCCTGCTCTGGGTGTCCTCCACACCAGAATCAGGG\n", file = "inputseq.fa")
}