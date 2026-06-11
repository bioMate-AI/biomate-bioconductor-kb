library(CRISPRseek)

input_file_path <- system.file("extdata", "inputseq.fa", package = "CRISPRseek")

if (file.exists(input_file_path)) {
    file.copy(input_file_path, "inputseq.fa", overwrite = TRUE)
} else {
    writeLines(c(
        ">Hsap_GATA1_ex2",
        "CCAGTTTGTGGATCCTGCTCTGGGTCCTCCACACCAGAATCAGGG"
    ), "inputseq.fa")
}