library(CRISPRseek)

inputFilePath <- system.file("extdata", "inputseq.fa", package = "CRISPRseek")

if (file.exists(inputFilePath)) {
    file.copy(inputFilePath, "inputseq.fa", overwrite = TRUE)
} else {
    fasta_content <- c(
        ">Hsap_GATA1_ex2",
        "CCAGTTTGTGGATCCTGCTCTGGGTGTCCTCCACACCAGAATCAGGGTGTGGAGGACACCAGAGCAGGCCAGAGCAGGATCCACAAACTGG"
    )
    writeLines(fasta_content, "inputseq.fa")
}