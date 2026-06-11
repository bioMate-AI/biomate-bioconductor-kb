library(CRISPRseek)

input_file <- system.file("extdata", "inputseq.fa", package = "CRISPRseek")

if (file.exists(input_file)) {
    file.copy(input_file, "inputseq.fa", overwrite = TRUE)
} else {
    # Fallback: create a small FASTA file matching the vignette's example
    fasta_content <- c(
        ">Hsap_GATA1_ex2",
        "CCAGTTTGTGGATCCTGCTCTGGTGTCCTCCACACCAGAATCAGGGGTGTGGAGGACACCAGAGCAGGCCAGAGCAGGATCCACAAACTGG"
    )
    writeLines(fasta_content, "inputseq.fa")
}